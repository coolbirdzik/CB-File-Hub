import * as React from "react";
import {
  CloudArrowUp,
  Cpu,
  FilePdf,
  Globe,
  LockKey,
  PictureInPicture,
  ShareNetwork,
  Tag,
  TerminalWindow,
  type Icon,
} from "@phosphor-icons/react";
import { T, type Copy, useCopy } from "./lang";

// The one marquee on the page: it shows breadth (what CB File Hub connects to and opens).
const items: Array<Copy & { icon: Icon }> = [
  { icon: ShareNetwork, en: "SMB shares", vi: "Thư mục SMB" },
  { icon: CloudArrowUp, en: "FTP", vi: "FTP" },
  { icon: LockKey, en: "SFTP", vi: "SFTP" },
  { icon: Globe, en: "WebDAV", vi: "WebDAV" },
  { icon: TerminalWindow, en: "SSH terminal", vi: "Terminal SSH" },
  { icon: PictureInPicture, en: "Picture-in-picture", vi: "Cửa sổ PiP" },
  { icon: FilePdf, en: "PDF preview", vi: "Xem trước PDF" },
  { icon: Tag, en: "Nested tags", vi: "Thẻ lồng nhau" },
  { icon: Cpu, en: "Local GGUF models", vi: "Mô hình GGUF tại máy" },
];

function Row({ hidden = false }: { hidden?: boolean }) {
  return (
    <ul aria-hidden={hidden || undefined} className={`flex shrink-0 items-center ${hidden ? "marquee-dupe" : ""}`}>
      {items.map(({ icon: Icon, en, vi }) => (
        <li key={en} className="px-2 sm:px-2.5">
          <span className="inline-flex items-center gap-3 rounded-2xl border border-line bg-surface/70 py-2 pr-5 pl-2 text-[15px] font-medium whitespace-nowrap text-ink/80 sm:text-base">
            <span className="grid size-9 place-items-center rounded-xl bg-accent-soft text-accent">
              <Icon size={19} weight="duotone" />
            </span>
            <T en={en} vi={vi} />
          </span>
        </li>
      ))}
    </ul>
  );
}

export function Marquee() {
  const copy = useCopy();
  return (
    <section
      aria-label={copy({ en: "Supported connections and formats", vi: "Kết nối và định dạng được hỗ trợ" })}
      className="marquee relative mt-20 overflow-hidden py-4 [mask-image:linear-gradient(90deg,transparent,#000_12%,#000_88%,transparent)] sm:mt-28"
    >
      <div className="marquee-track flex w-max">
        <Row />
        <Row hidden />
      </div>
    </section>
  );
}
