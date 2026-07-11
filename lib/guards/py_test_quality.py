#!/usr/bin/env python3
"""SOSL guard helper: reject low-quality tests that game a coverage metric.

A coverage metric rewards *executed* lines; the built-in guards only scan diff
*patterns*. Neither checks whether a test actually asserts anything. This helper
AST-parses every NEW or MODIFIED test file (vs git HEAD) in the worktree and
fails on the highest-confidence ways an autonomous loop inflates coverage without
testing behavior:

  1. A test function with nothing that can fail — no assert, no pytest.raises/
     warns/fail, no assert*-named call, no raise_for_status().
  2. A test whose only assertions are constants (`assert True`, `assert 1`).
  3. Coverage farming by import: pkgutil.walk_packages / bulk importlib.import_module.
  4. New xfail marks (the body runs and banks coverage while the suite stays green).
  5. Unfailable tests: contextlib.suppress(...) or bare `except: pass` around the call.

Exit 0 = clean, exit 1 = violation (reasons printed to stdout). Read-only.

Finding (1), "no assertion", is a WARNING by default: a legitimate "must not raise"
test (call something, pass iff it doesn't throw) is shape-identical to a hollow one,
so hard-failing it produces false positives. It is surfaced for the Judge instead.
The unambiguous gaming signals (2-5) always hard-fail. Set SOSL_TEST_QUALITY_STRICT=1
to also hard-fail (1) in domains where every test must carry an explicit assertion.

Usage: py_test_quality.py <target_dir>
"""
import ast
import os
import subprocess
import sys


def changed_test_files(target):
    try:
        out = subprocess.run(
            ["git", "-C", target, "diff", "--name-only", "--diff-filter=AM", "HEAD"],
            capture_output=True, text=True, check=False,
        ).stdout
    except Exception:
        return []
    files = []
    for line in out.splitlines():
        line = line.strip()
        if not line.endswith(".py"):
            continue
        base = os.path.basename(line)
        if (base.startswith("test_") or base.endswith("_test.py")
                or base == "conftest.py" or "/tests/" in line or line.startswith("tests/")):
            files.append(line)
    return files


# Call names that count as a real behavioural check even without a bare `assert`.
CHECK_CALL_NAMES = {
    "raises", "warns", "fail", "raise_for_status", "check", "expect",
    "assertRaises", "assertRaisesRegex", "assertWarns",
}


def _call_name(func):
    if isinstance(func, ast.Attribute):
        return func.attr
    if isinstance(func, ast.Name):
        return func.id
    return ""


def func_has_real_check(fn):
    """True if the function contains something that can actually fail a test."""
    for node in ast.walk(fn):
        if isinstance(node, ast.Assert):
            # A non-constant assert is a real check; `assert True` is not.
            if not isinstance(node.test, ast.Constant):
                return True
        elif isinstance(node, ast.Call):
            name = _call_name(node.func)
            if name.startswith("assert") or name in CHECK_CALL_NAMES:
                return True
        elif isinstance(node, ast.With):
            for item in node.items:
                c = item.context_expr
                if isinstance(c, ast.Call) and _call_name(c.func) in ("raises", "warns"):
                    return True
    return False


def func_only_constant_asserts(fn):
    """True if the function HAS asserts and every one of them is a constant."""
    asserts = [n for n in ast.walk(fn) if isinstance(n, ast.Assert)]
    if not asserts:
        return False
    return all(isinstance(a.test, ast.Constant) for a in asserts)


def has_xfail(tree):
    for node in ast.walk(tree):
        if isinstance(node, ast.Attribute) and node.attr == "xfail":
            return True
        if isinstance(node, ast.Name) and node.id == "xfail":
            return True
    return False


def has_import_farming(tree):
    # Only BULK enumeration is farming. A single importlib.import_module(name) is a
    # legitimate dynamic-dispatch pattern in real tests, so it does not count.
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and _call_name(node.func) in ("walk_packages", "iter_modules"):
            return True
    return False


BROAD_EXC = {"Exception", "BaseException"}


def _is_broad_exc(node):
    """True for a bare/broad exception (None, Exception, BaseException); a narrow
    `except ValueError` or `suppress(KeyError)` is a legitimate tolerated error."""
    if node is None:
        return True
    if isinstance(node, ast.Name):
        return node.id in BROAD_EXC
    if isinstance(node, ast.Attribute):
        return node.attr in BROAD_EXC
    return False


def has_unfailable_swallow(tree):
    for node in ast.walk(tree):
        # contextlib.suppress(Exception) — broad suppression only
        if isinstance(node, ast.Call) and _call_name(node.func) == "suppress":
            if any(_is_broad_exc(a) for a in node.args):
                return True
        # `except:` / `except Exception:` whose body is just `pass` (narrow types are fine)
        if isinstance(node, ast.ExceptHandler):
            body = node.body
            if len(body) == 1 and isinstance(body[0], ast.Pass) and _is_broad_exc(node.type):
                return True
    return False


def is_fixture(fn):
    """A pytest fixture named test_* is not a test — skip it."""
    for d in fn.decorator_list:
        node = d.func if isinstance(d, ast.Call) else d
        if _call_name(node) == "fixture":
            return True
    return False


def test_functions(tree):
    for node in ast.walk(tree):
        if (isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
                and node.name.startswith("test") and not is_fixture(node)):
            yield node


def main():
    if len(sys.argv) < 2:
        print("py_test_quality: missing target dir", file=sys.stderr)
        return 2
    target = sys.argv[1]
    strict = os.environ.get("SOSL_TEST_QUALITY_STRICT", "0") == "1"

    violations = []
    warnings = []
    for rel in changed_test_files(target):
        path = os.path.join(target, rel)
        try:
            src = open(path, encoding="utf-8").read()
            tree = ast.parse(src, filename=rel)
        except (OSError, SyntaxError):
            continue  # unreadable / unparsable is not this guard's concern

        if has_import_farming(tree):
            violations.append(f"{rel}: coverage farming by import (walk_packages/iter_modules) — imports modules instead of testing them")
        if has_xfail(tree):
            violations.append(f"{rel}: xfail mark — the body runs and banks coverage while the suite stays green")
        if has_unfailable_swallow(tree):
            violations.append(f"{rel}: exception-swallowing (contextlib.suppress / except: pass) makes a test unfailable")

        for fn in test_functions(tree):
            if func_only_constant_asserts(fn):
                violations.append(f"{rel}:{fn.lineno} {fn.name}: only trivial constant assertions (e.g. `assert True`)")
            elif not func_has_real_check(fn):
                msg = f"{rel}:{fn.lineno} {fn.name}: no assertion — nothing in this test can fail"
                (violations if strict else warnings).append(msg)

    for w in warnings:
        print(f"WARN test-quality: {w}")
    if violations:
        print("GUARD FAIL: test-quality violations (tests raise coverage without testing behaviour):")
        for v in violations:
            print(f"  - {v}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
