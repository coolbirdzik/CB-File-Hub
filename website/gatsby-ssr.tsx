import * as React from "react";
import type { GatsbySSR } from "gatsby";

import "@fontsource-variable/inter";
import "@fontsource/be-vietnam-pro/400.css";
import "@fontsource/be-vietnam-pro/500.css";
import "@fontsource/be-vietnam-pro/600.css";
import "@fontsource/be-vietnam-pro/700.css";
import "./src/styles/global.css";

// Same resolution order as static/lang.js (used by the demo and legal pages):
// ?lang= query, then saved choice, then browser language.
const pickLanguage = `(function(){var r=document.documentElement,l="en";try{var q=new URLSearchParams(location.search).get("lang"),s=localStorage.getItem("cbfh-lang");l=q==="en"||q==="vi"?q:s==="en"||s==="vi"?s:(navigator.language||"").toLowerCase().indexOf("vi")===0?"vi":"en"}catch(e){}r.setAttribute("data-lang",l);r.setAttribute("lang",l)})();`;

export const onRenderBody: GatsbySSR["onRenderBody"] = ({ setHtmlAttributes, setHeadComponents }) => {
  setHtmlAttributes({ lang: "en" });
  setHeadComponents([
    <script key="cbfh-lang" dangerouslySetInnerHTML={{ __html: pickLanguage }} />,
  ]);
};
