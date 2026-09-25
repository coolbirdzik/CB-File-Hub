import * as React from "react";

export type Lang = "en" | "vi";
export type Copy = { en: string; vi: string };

const STORAGE_KEY = "cbfh-lang";

const titles: Copy = {
  en: "CB File Hub - Your files, in flow",
  vi: "CB File Hub - Mọi tệp tin, trong tầm tay",
};

type LangState = { lang: Lang; setLang: (lang: Lang) => void };

const LangContext = React.createContext<LangState>({ lang: "en", setLang: () => {} });

function readDocumentLang(): Lang {
  return document.documentElement.getAttribute("data-lang") === "vi" ? "vi" : "en";
}

export function LangProvider({ children }: { children: React.ReactNode }) {
  // SSR and the first client render always use "en" so hydration matches.
  // Visible copy is unaffected: <T> renders both languages and CSS hides one.
  const [lang, setLangState] = React.useState<Lang>("en");

  React.useEffect(() => {
    const initial = readDocumentLang();
    setLangState(initial);
    document.title = titles[initial];
  }, []);

  const setLang = React.useCallback((next: Lang) => {
    const root = document.documentElement;
    root.setAttribute("data-lang", next);
    root.setAttribute("lang", next);
    try {
      localStorage.setItem(STORAGE_KEY, next);
    } catch {
      // Storage can be blocked; the choice then lasts for this page view only.
    }
    document.title = titles[next];
    setLangState(next);
  }, []);

  const value = React.useMemo(() => ({ lang, setLang }), [lang, setLang]);
  return <LangContext.Provider value={value}>{children}</LangContext.Provider>;
}

export function useLang() {
  return React.useContext(LangContext);
}

/** Picks a string for attributes (alt, aria-label) that cannot hold two spans. */
export function useCopy() {
  const { lang } = useLang();
  return React.useCallback((copy: Copy) => copy[lang], [lang]);
}

/** Bilingual inline text. Both spans ship in the HTML; a data-lang rule hides the inactive one. */
export function T({ en, vi }: Copy) {
  return (
    <>
      <span data-l="en" lang="en">
        {en}
      </span>
      <span data-l="vi" lang="vi">
        {vi}
      </span>
    </>
  );
}

export const pageTitle = titles;
