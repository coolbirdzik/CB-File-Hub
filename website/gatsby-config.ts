import type { GatsbyConfig } from "gatsby";

const config: GatsbyConfig = {
  siteMetadata: {
    title: "CB File Hub",
    siteUrl: "https://coolbird.net",
  },
  // Pages serves Gatsby's directory index pages with a trailing slash.
  trailingSlash: "always",
  graphqlTypegen: false,
  plugins: ["gatsby-plugin-postcss"],
};

export default config;
