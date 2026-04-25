/**
 * queries/codeql/security-queries.ql
 *
 * Starter CodeQL query file for security-platform-toolchain.
 * Import this file or run individual queries against a CodeQL database.
 *
 * Usage:
 *   codeql database analyze <db> queries/codeql/ \
 *     --format=sarif-latest --output=results.sarif
 */

/**
 * @name Buffer not checked before use
 * @description A buffer returned from a function is used without checking
 *              whether the allocation succeeded (NULL pointer dereference risk).
 * @kind problem
 * @problem.severity warning
 * @id spt/cpp/unchecked-alloc
 * @tags security
 *       correctness
 *       external/cwe/cwe-476
 */

import cpp
import semmle.code.cpp.dataflow.DataFlow

from FunctionCall alloc, Variable v, Expr use
where
  alloc.getTarget().getName() in ["malloc", "calloc", "realloc"] and
  v.getInitializer().getExpr() = alloc and
  use = v.getAnAccess() and
  not exists(IfStmt guard |
    guard.getCondition().(EqualityOperation).getAnOperand() = v.getAnAccess() and
    guard.getCondition().(EqualityOperation).getAnOperand().(Literal).getValue() = "0"
  )
select use,
  "Pointer $@ from " + alloc.getTarget().getName() +
  "() is used without a NULL check.",
  v, v.getName()

// ---------------------------------------------------------------------------

/**
 * @name Use of dangerous C function
 * @description Calls to functions known to be unsafe (gets, strcpy, sprintf).
 * @kind problem
 * @problem.severity error
 * @id spt/cpp/dangerous-function
 * @tags security
 *       correctness
 *       external/cwe/cwe-120
 */

import cpp

from FunctionCall call
where
  call.getTarget().getName() in [
    "gets", "strcpy", "strcat", "sprintf", "vsprintf",
    "scanf", "fscanf", "sscanf"
  ]
select call,
  "Call to unsafe function '" + call.getTarget().getName() +
  "' — consider a bounds-checked alternative."

// ---------------------------------------------------------------------------

/**
 * @name Format string injection
 * @description A format string argument is not a string literal, which may
 *              allow format-string injection.
 * @kind problem
 * @problem.severity error
 * @id spt/cpp/format-string-injection
 * @tags security
 *       external/cwe/cwe-134
 */

import cpp

from FunctionCall call, int idx
where
  (
    call.getTarget().getName() in ["printf", "fprintf", "sprintf",
                                    "snprintf", "vprintf", "vfprintf"] and
    idx = call.getTarget().getName().matches("%fprintf") or
    call.getTarget().getName().matches("%printf") and idx = 0
  ) and
  not call.getArgument(idx) instanceof StringLiteral
select call.getArgument(idx),
  "Non-literal format string passed to " + call.getTarget().getName() +
  "() — potential format-string injection."
