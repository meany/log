const { DateTime } = require("luxon");
const fs = require("node:fs");
const path = require("node:path");
const pluginRss = require("@11ty/eleventy-plugin-rss");
const syntaxHighlight = require("@11ty/eleventy-plugin-syntaxhighlight");
const markdownIt = require("markdown-it");
const markdownItAnchor = require("markdown-it-anchor");
const htmlmin = require("html-minifier-terser");

const EXCLUDED_TAGS = new Set(["all", "nav", "post", "entries", "tagList"]);

module.exports = function (eleventyConfig) {
  const rootDir = process.cwd();
  const localAssetExists = (assetPath) => {
    const clean = assetPath.split("?")[0].split("#")[0];
    const relative = clean.replace(/^\//, "");
    const candidates = [
      path.join(rootDir, "static", relative),
      path.join(rootDir, relative),
      path.join(rootDir, "content", relative),
    ];
    return candidates.some((filePath) => fs.existsSync(filePath));
  };

  eleventyConfig.addPlugin(pluginRss);
  eleventyConfig.addPlugin(syntaxHighlight);

  eleventyConfig.addFilter("socialImagePath", (imagePath) => {
    const fallback = "/og-image.svg";
    if (!imagePath) {
      return fallback;
    }
    if (/^https?:\/\//i.test(imagePath)) {
      return imagePath;
    }
    if (imagePath.startsWith("/") && localAssetExists(imagePath)) {
      return imagePath;
    }
    return fallback;
  });

  eleventyConfig.addFilter("socialImageType", (imagePath) => {
    const assetPath = imagePath || "/og-image.svg";
    const extension = path.extname(assetPath.split("?")[0].split("#")[0]).toLowerCase();

    switch (extension) {
      case ".png":
        return "image/png";
      case ".jpg":
      case ".jpeg":
        return "image/jpeg";
      case ".webp":
        return "image/webp";
      case ".gif":
        return "image/gif";
      default:
        return "image/svg+xml";
    }
  });

  // Configure markdown-it with heading anchor IDs (required for ToC links)
  const md = markdownIt({ html: true, linkify: true })
    .use(markdownItAnchor);
  eleventyConfig.setLibrary("md", md);

  // Add heading permalink icons and copy buttons for code blocks.
  eleventyConfig.addTransform("htmlEnhancements", (content, outputPath) => {
    if (!outputPath?.endsWith(".html")) {
      return content;
    }

    let enhanced = content.replace(/<h([23])([^>]*)>([\s\S]*?)<\/h\1>/gi, (match, level, attrs, inner) => {
      const idMatch = attrs.match(/\sid="([^"]+)"/i);
      if (!idMatch) {
        return match;
      }
      const id = idMatch[1];

      if (inner.includes("class=\"heading-anchor\"")) {
        return match;
      }

      const anchor = `<a class="heading-anchor" href="#${id}" aria-label="Link to this section"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false"><path d="M10 13a5 5 0 0 0 7.07 0l2.83-2.83a5 5 0 0 0-7.07-7.07L11 4"/><path d="M14 11a5 5 0 0 0-7.07 0L4.1 13.83a5 5 0 0 0 7.07 7.07L13 20"/></svg></a>`;
      return `<h${level}${attrs}>${inner}${anchor}</h${level}>`;
    });

    enhanced = enhanced.replace(/<pre([^>]*)>\s*<code([^>]*)>([\s\S]*?)<\/code>\s*<\/pre>/gi, (match, preAttrs, codeAttrs, codeBody) => {
      const isAscii = /class\s*=\s*"[^"]*ascii-hero[^"]*"/i.test(preAttrs);
      if (isAscii) {
        return match;
      }

      const isDiff = /class\s*=\s*"[^"]*language-diff[^"]*"/i.test(preAttrs) || /class\s*=\s*"[^"]*language-diff[^"]*"/i.test(codeAttrs);
      if (isDiff) {
        return `<div class="code-block code-block-diff"><p class="code-block-label" aria-label="Update to original post">Entry Updates</p><pre${preAttrs}><code${codeAttrs}>${codeBody}</code></pre></div>`;
      }

      return `<div class="code-block"><button type="button" class="code-copy-btn" aria-label="Copy to clipboard" title="Copy to clipboard"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg></button><pre${preAttrs}><code${codeAttrs}>${codeBody}</code></pre></div>`;
    });

    return enhanced;
  });

  // Minify HTML output — preserves whitespace inside <pre>
  eleventyConfig.addTransform("htmlmin", async (content, outputPath) => {
    if (outputPath?.endsWith(".html")) {
      return await htmlmin.minify(content, {
        collapseWhitespace: true,
        conservativeCollapse: true,
        removeComments: true,
        minifyJS: true,
        removeRedundantAttributes: true,
        removeScriptTypeAttributes: true,
        removeStyleLinkTypeAttributes: true,
        useShortDoctype: true,
      });
    }
    return content;
  });

  // Table of contents: extract h2/h3 with anchor IDs from rendered HTML
  eleventyConfig.addFilter("toc", (content) => {
    const headings = [];
    const re = /<h([23])[^>]+id="([^"]+)"[^>]*>([\s\S]*?)<\/h\1>/gi;
    let m;
    while ((m = re.exec(content)) !== null) {
      headings.push({
        level: parseInt(m[1]),
        id: m[2],
        text: m[3].replace(/<[^>]+>/g, "").trim(),
      });
    }
    if (headings.length < 2) return "";
    let h2Count = 0;
    let items = "";
    for (const h of headings) {
      if (h.level === 2) {
        h2Count++;
        items += `<li><a href="#${h.id}">${h2Count}.\u00a0${h.text}</a></li>`;
      } else {
        items += `<li class="toc-h3"><a href="#${h.id}">${h.text}</a></li>`;
      }
    }
    return `<nav class="toc" aria-label="Table of contents"><p class="toc-title">Contents</p><ol>${items}</ol></nav>`;
  });

  eleventyConfig.addPassthroughCopy("css");
  eleventyConfig.addPassthroughCopy("static");

  eleventyConfig.addFilter("readableDate", (dateObj) => {
    return DateTime.fromJSDate(dateObj, { zone: "utc" }).toFormat("yyyy-LL-dd");
  });

  eleventyConfig.addFilter("isoDate", (dateObj) => {
    return DateTime.fromJSDate(dateObj, { zone: "utc" }).toISO();
  });

  eleventyConfig.addCollection("entries", function (collectionApi) {
    return collectionApi.getFilteredByGlob("content/entries/*.md").sort((a, b) => b.date - a.date);
  });

  eleventyConfig.addCollection("tagList", function (collectionApi) {
    const tagSet = new Set();
    for (const item of collectionApi.getAll()) {
      const tags = item.data.tags || [];
      for (const tag of tags) {
        if (!EXCLUDED_TAGS.has(tag)) {
          tagSet.add(tag);
        }
      }
    }
    return [...tagSet].sort((a, b) => a.localeCompare(b));
  });

  return {
    dir: {
      includes: "_includes",
      output: "_site"
    },
    markdownTemplateEngine: "njk",
    htmlTemplateEngine: "njk"
  };
};