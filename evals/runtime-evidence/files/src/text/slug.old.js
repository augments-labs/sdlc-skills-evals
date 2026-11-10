// The slugify that src/text/slug.js replaced. Kept for comparison.
function slugify(title) {
  return title
    .toLowerCase()
    .split('')
    .map((ch) => ((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') ? ch : ' '))
    .join('')
    .split(' ')
    .filter((word) => word.length > 0)
    .join('-');
}

module.exports = { slugify };
