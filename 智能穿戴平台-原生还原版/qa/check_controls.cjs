const fs = require("node:fs");
const pages = JSON.parse(fs.readFileSync("qa/page-checks.json", "utf8"));
const source =
  fs.readFileSync("js/actions.js", "utf8") +
  fs.readFileSync("js/ui.js", "utf8");
const names = [...new Set(pages.flatMap((p) => p.actions))];
const missing = names.filter(
  (name) =>
    !source.includes("'" + name + "'") && !source.includes('"' + name + '"'),
);
if (missing.length)
  throw Error("Missing visible action implementation: " + missing.join(", "));
if (
  pages.some(
    (p) => p.unloadedImages || p.scrollHeight > 941 || p.scrollWidth > 1672,
  )
)
  throw Error("Page viewport check failed");
console.log(
  `${pages.length} pages / ${names.length} visible action names checked; no missing action implementation or viewport overflow.`,
);
