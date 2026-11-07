import * as React from "react";
import type { HeadFC } from "gatsby";
import { Layout, Seo } from "../components/Layout";
import { Hero } from "../components/Hero";
import { LocalSubtitles } from "../components/LocalSubtitles";
import { Marquee } from "../components/Marquee";
import { Tour } from "../components/Tour";
import { Bento } from "../components/Bento";
import { Platforms } from "../components/Platforms";
import { Download } from "../components/Download";
import { pageTitle } from "../components/lang";
import { links } from "../components/site";

const description =
  "CB File Hub combines a file manager, local AI video subtitles, SSH/SFTP, media libraries and a disk cleaner. AI subtitle generation and translation are desktop-only.";

// Structured data so search engines can show CB File Hub as an app with its platforms.
const softwareApp = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "CB File Hub",
  url: "https://coolbird.net/",
  description,
  applicationCategory: "UtilitiesApplication",
  operatingSystem: links.linux ? "Windows, macOS, Linux, Android" : "Windows, macOS, Android",
  image: "https://coolbird.net/media/hero-browser.webp",
  downloadUrl: "https://coolbird.net/#download",
  featureList: [
    "Tabbed file manager with split panes",
    "Local AI subtitle generation and translation on desktop",
    "SSH client, SFTP transfers and SSH tunnels",
    "SMB, FTP and WebDAV network shares",
    "AI file assistant with local GGUF models",
    "Disk cleaner with Smart Clean",
    "Photo and video library",
    "Hierarchical file tags",
    "Torrent library",
  ],
};

export default function IndexPage() {
  return (
    <Layout>
      <Hero />
      <Marquee />
      <LocalSubtitles />
      <Tour />
      <Bento />
      <Platforms />
      <Download />
    </Layout>
  );
}

export const Head: HeadFC = () => (
  <>
    <Seo title={pageTitle.en} description={description} image="/media/subtitles-promo-en.webp" />
    <script type="application/ld+json">{JSON.stringify(softwareApp)}</script>
    <link rel="preload" as="image" href="/media/hero-browser.webp" />
  </>
);
