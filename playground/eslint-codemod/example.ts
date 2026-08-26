// eslint-codemod playground.
//
// Open this file in Neovim, place the cursor after one of the trigger
// markers below, and the eslint-codemod plugin will:
//   1. Show completions filtered to commands valid in the current comment
//   2. Run the Node lint worker against the *real* eslint in this dir
//      to decide which items are fixable
//   3. On select + autoFix, run `source.fixAll.eslint` to apply the change
//
// All blocks below are SELF-CONTAINED so you can delete one without
// breaking the others. We deliberately avoid TypeScript syntax so the
// playground doesn't need @typescript-eslint as a dep.

let result
/// to-ternary
if (value > 0)
  result = 'positive'
else
  result = 'non-positive'
// __done__ to-ternary

/// reverse-if-else
if (value === 1)
  doB()
else
  doA()
// __done__ reverse-if-else

function add(a, b) {
  return a + b
}
/// to-arrow
add(1, 2)
// __done__ to-arrow

const obj = { a: 1, b: 2 }
const foo = obj.a
const bar = obj.b
/// to-destructuring
console.log(foo, bar)
// __done__ to-destructuring

const greet = name => `hello ${name}`
/// to-function
greet('world')
// __done__ to-function

const nums = [3, 1, 4, 1, 5, 9, 2, 6]
// @keep-sorted
console.log(nums)
// __done__ keep-sorted

const dupes = [1, 1, 2, 2, 3, 3, 4]
// @keep-unique
console.log(dupes)
// __done__ keep-unique

const phoneRe = /^\+?\d{1,3}[\s-]?\(?\d{1,4}\)?[\s-]?\d{3,4}[\s-]?\d{3,4}$/
// @regex101
phoneRe.test('+1 555 123 4567')
// __done__ regex101

const value = 1
function doA() {}
function doB() {}
