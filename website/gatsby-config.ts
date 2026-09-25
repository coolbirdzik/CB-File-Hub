import type { GatsbyConfig } from "gatsby";

const config: GatsbyConfig = {
  siteMetadata: {
    title: "CB File Hub",
    siteUrl: "https://cbfilehub.web.app",
  },
  // Firebase Hosting serves with `trailingSlash: false`, keep Gatsby links in sync.
  trailingSlash: "never",
  graphqlTypegen: false,
  plugins: ["gatsby-plugin-postcss"],
};

export default config;
