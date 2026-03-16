const fs = require("node:fs");
const path = require("node:path");
const site = require("../../_data/site.js");

const rootDir = process.cwd();
const resolveSocialImage = (imagePath) => {
  const fallback = "/og-image.svg";
  if (!imagePath) {
    return fallback;
  }
  if (/^https?:\/\//i.test(imagePath)) {
    return imagePath;
  }
  if (!imagePath.startsWith("/")) {
    return fallback;
  }

  const relative = imagePath.split("?")[0].split("#")[0].replace(/^\//, "");
  const candidates = [
    path.join(rootDir, "static", relative),
    path.join(rootDir, relative),
    path.join(rootDir, "content", relative),
  ];
  return candidates.some((filePath) => fs.existsSync(filePath)) ? imagePath : fallback;
};

module.exports = {
  layout: "entry.njk",
  tags: ["entries"],
  permalink: (data) => {
    if (process.env.ELEVENTY_ENV === "production" && data.draft === true) {
      return false;
    }
    const slug = data.slug || data.page.fileSlug;
    return `/entries/${slug}/`;
  },
  eleventyComputed: {
    title: (data) => data.title,
    description: (data) => data.summary || `Field log entry from ${site.name}`,
    og_image: (data) => resolveSocialImage(data.og_image || data.featured_image)
  }
};