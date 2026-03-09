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
    title: (data) => data.title
  }
};