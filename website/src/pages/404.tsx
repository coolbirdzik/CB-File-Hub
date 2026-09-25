import * as React from "react";
import type { HeadFC } from "gatsby";
import { ArrowLeft } from "@phosphor-icons/react";
import { Layout, Seo } from "../components/Layout";
import { T } from "../components/lang";
import { Rise } from "../components/motion";

export default function NotFoundPage() {
  return (
    <Layout>
      <section className="mx-auto flex min-h-[100dvh] max-w-7xl flex-col justify-center px-4 pt-24 pb-16 sm:px-6 lg:px-8">
        <Rise>
          <p className="text-sm font-semibold text-accent">404</p>
          <h1 className="mt-4 text-5xl leading-[1.0] font-extrabold tracking-[-0.015em] uppercase sm:text-7xl">
            <T en="Page not found." vi="Không tìm thấy trang." />
          </h1>
          <p className="mt-5 max-w-[48ch] text-lg leading-relaxed text-muted">
            <T
              en="The link may be old, or the page has moved."
              vi="Liên kết có thể đã cũ, hoặc trang đã được chuyển đi."
            />
          </p>
          <a
            href="/"
            className="mt-9 inline-flex h-12 items-center gap-2 rounded-full bg-accent px-6 font-semibold text-accent-ink transition-transform active:scale-[0.98]"
          >
            <ArrowLeft size={16} weight="bold" />
            <T en="Back to home" vi="Về trang chủ" />
          </a>
        </Rise>
      </section>
    </Layout>
  );
}

export const Head: HeadFC = () => (
  <Seo title="Page not found - CB File Hub" description="This page does not exist." path="/404" />
);
