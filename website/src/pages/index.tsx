import * as React from "react";
import type { HeadFC } from "gatsby";
import { Layout, Seo } from "../components/Layout";
import { Hero } from "../components/Hero";
import { Marquee } from "../components/Marquee";
import { LiveDemo } from "../components/LiveDemo";
import { Tour } from "../components/Tour";
import { Bento } from "../components/Bento";
import { Platforms } from "../components/Platforms";
import { Download } from "../components/Download";
import { pageTitle } from "../components/lang";

export default function IndexPage() {
  return (
    <Layout>
      <Hero />
      <Marquee />
      <LiveDemo />
      <Tour />
      <Bento />
      <Platforms />
      <Download />
    </Layout>
  );
}

export const Head: HeadFC = () => (
  <>
    <Seo
      title={pageTitle.en}
      description="CB File Hub brings files, media, tags, network locations and an AI assistant into one focused workspace for Windows and Android."
    />
    <link rel="preload" as="image" href="/media/hero-browser.webp" />
  </>
);
