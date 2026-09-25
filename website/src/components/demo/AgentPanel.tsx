import * as React from "react";
import {
  CaretDown,
  ChatsCircle,
  Cpu,
  FolderSimple,
  PaperPlaneRight,
  Sparkle,
  Warning,
  X,
} from "@phosphor-icons/react";
import { byId, entries, type Entry, filesWithTag, tags } from "./data";
import { useDemo } from "./context";
import { FileGlyph } from "./ui";

type AgentReply = {
  role: "agent";
  text: string;
  files?: string[];
  approval?: { files: string[]; state: "pending" | "approved" | "denied" };
};
type Message = { id: number; role: "user"; text: string } | ({ id: number } & AgentReply);

// Scripted replies only: the demo never calls a model. Matching is deliberately simple.
function reply(prompt: string, t: (en: string, vi: string) => string): AgentReply {
  const p = prompt.toLowerCase();
  const files = entries.filter((e) => e.kind !== "folder" && e.kind !== "drive");

  if (/delete|remove|xóa|xoá/.test(p)) {
    const dupes = files.filter((e) => /\(copy\)|\(1\)/.test(e.name)).map((e) => e.id);
    return {
      role: "agent",
      text: t(`Confirm: Delete ${dupes.length} files`, `Xác nhận: Xóa ${dupes.length} tệp`),
      files: dupes,
      approval: { files: dupes, state: "pending" },
    };
  }
  if (/dup|trùng/.test(p)) {
    return {
      role: "agent",
      text: t(
        "I found 2 potential duplicates in your library. They have the same size and name as files in Pictures and Videos. Want me to highlight them so you can decide?",
        "Mình tìm thấy 2 tệp có thể bị trùng trong thư viện. Chúng có cùng kích thước và tên với tệp trong Pictures và Videos. Bạn muốn mình đánh dấu để bạn quyết định không?",
      ),
      files: ["w3", "v5"],
    };
  }
  const asksTag = /tag|thẻ|nhãn/.test(p);
  const tag = tags.find((x) => p.includes(x.name.en.toLowerCase()) || p.includes(x.name.vi.toLowerCase()));
  if (asksTag && tag) {
    const hits = filesWithTag(tag.id);
    return {
      role: "agent",
      text: t(`${hits.length} files are tagged ${tag.name.en}:`, `Có ${hits.length} tệp mang thẻ ${tag.name.vi}:`),
      files: hits.map((e) => e.id),
    };
  }
  if (asksTag) {
    return {
      role: "agent",
      text: t(
        `Which tag? You have ${tags.map((x) => x.name.en).slice(0, 6).join(", ")} and more.`,
        `Thẻ nào nhỉ? Bạn có ${tags.map((x) => x.name.vi).slice(0, 6).join(", ")} và các thẻ khác.`,
      ),
    };
  }
  if (/video|phim|large|lớn/.test(p)) {
    const vids = files.filter((e) => e.kind === "video").sort((a, b) => (b.size ?? 0) - (a.size ?? 0));
    return { role: "agent", text: t(`Here are your ${vids.length} videos, largest first:`, `Đây là ${vids.length} video của bạn, lớn nhất trước:`), files: vids.map((e) => e.id) };
  }
  if (/photo|image|picture|ảnh|hình|recent|gần/.test(p)) {
    const imgs = files.filter((e) => e.kind === "image").sort((a, b) => b.modified.localeCompare(a.modified)).slice(0, 5);
    return { role: "agent", text: t("Your most recent photos:", "Những ảnh gần đây nhất của bạn:"), files: imgs.map((e) => e.id) };
  }
  if (tag) {
    const hits = filesWithTag(tag.id);
    return {
      role: "agent",
      text: t(`${hits.length} files are tagged ${tag.name.en}:`, `Có ${hits.length} tệp mang thẻ ${tag.name.vi}:`),
      files: hits.map((e) => e.id),
    };
  }
  const words = p.split(/\s+/).filter((w) => w.length > 2);
  const hits = files.filter((e) => words.some((w) => e.name.toLowerCase().includes(w)));
  if (hits.length) {
    return { role: "agent", text: t(`I found ${hits.length} matching files:`, `Mình tìm thấy ${hits.length} tệp phù hợp:`), files: hits.map((e) => e.id) };
  }
  return {
    role: "agent",
    text: t(
      'This demo answers from a small script. Try "find recent photos", "show large videos", "files tagged Travel", "find duplicates" or "delete the copies".',
      'Bản demo trả lời theo kịch bản có sẵn. Thử "tìm ảnh gần đây", "hiện video lớn", "tệp có thẻ Du lịch", "tìm tệp trùng" hoặc "xóa các bản sao".',
    ),
  };
}

export function AgentPanel({ onClose, folderId }: { onClose: () => void; folderId: string | null }) {
  const { t, navigate, toast } = useDemo();
  const [messages, setMessages] = React.useState<Message[]>([]);
  const [draft, setDraft] = React.useState("");
  const [thinking, setThinking] = React.useState(false);
  const scroller = React.useRef<HTMLDivElement>(null);
  const nextId = React.useRef(1);

  React.useEffect(() => {
    scroller.current?.scrollTo({ top: scroller.current.scrollHeight, behavior: "smooth" });
  }, [messages, thinking]);

  const send = (text: string) => {
    const clean = text.trim();
    if (!clean || thinking) return;
    setMessages((m) => [...m, { id: nextId.current++, role: "user", text: clean }]);
    setDraft("");
    setThinking(true);
    window.setTimeout(() => {
      setMessages((m) => [...m, { id: nextId.current++, ...reply(clean, t) }]);
      setThinking(false);
    }, 650);
  };

  const decide = (id: number, state: "approved" | "denied") => {
    setMessages((m) => m.map((msg) => (msg.id === id && msg.role === "agent" && msg.approval ? { ...msg, approval: { ...msg.approval, state } } : msg)));
    if (state === "approved") toast(t("Demo only: nothing was deleted. The app moves files to Trash.", "Chỉ là demo: không có gì bị xóa. App sẽ chuyển tệp vào Thùng rác."));
  };

  const reveal = (e: Entry) => {
    if (e.parent) navigate(`fs:${e.parent}`, e.id);
  };

  const suggestions = [
    t("Find recent photos", "Tìm ảnh gần đây"),
    t("Show large videos", "Hiện video lớn"),
    t("Files tagged as...", "Tệp có nhãn là..."),
  ];
  const folder = folderId ? byId.get(folderId) : null;

  return (
    <aside aria-label="CB Agent" className="flex h-full w-full flex-col bg-app-bg">
      <div className="flex h-11 shrink-0 items-center gap-2 border-b border-app-line px-3">
        <ChatsCircle size={17} weight="light" className="text-app-muted" />
        <Sparkle size={16} weight="light" className="text-app-accent" />
        <span className="text-[13.5px] font-semibold">CB Agent</span>
        <span className="ml-auto inline-flex items-center gap-1.5 rounded-md px-2 py-1 text-[11px] text-app-muted hover:bg-app-hover">
          <Cpu size={13} weight="light" />
          Qwen3.5 4B · Q4_K_M
          <CaretDown size={10} />
        </span>
        <button type="button" aria-label={t("Close", "Đóng")} onClick={onClose} className="grid size-7 place-items-center rounded-md text-app-muted hover:bg-app-hover">
          <X size={15} weight="light" />
        </button>
      </div>

      <div ref={scroller} className="min-h-0 flex-1 space-y-3 overflow-y-auto p-3">
        {messages.length === 0 && (
          <div className="rounded-xl bg-app-field/70 px-3.5 py-3 text-[12.5px] leading-relaxed">
            {t(
              "Hi! I can search, sort and inspect the files in this sample library. I always ask before changing anything.",
              "Chào bạn! Mình có thể tìm, sắp xếp và xem thông tin tệp trong thư viện mẫu này. Mình luôn hỏi trước khi thay đổi bất cứ thứ gì.",
            )}
          </div>
        )}
        {messages.map((m) =>
          m.role === "user" ? (
            <div key={m.id} className="flex justify-end">
              <div className="max-w-[85%] rounded-2xl rounded-br-md bg-app-accent px-3.5 py-2 text-[12.5px] text-white">{m.text}</div>
            </div>
          ) : (
            <div key={m.id} className="max-w-[94%] rounded-2xl rounded-bl-md bg-app-field/80 px-3.5 py-2.5 text-[12.5px] leading-relaxed">
              {m.approval && <Warning size={15} weight="light" className="mb-1 inline-block text-[#c46a00]" />}{" "}
              {m.text}
              {m.files && m.files.length > 0 && (
                <div className="mt-2 flex flex-col gap-1">
                  {m.files.slice(0, 6).map((id) => {
                    const e = byId.get(id)!;
                    return (
                      <button
                        key={id}
                        type="button"
                        onClick={() => reveal(e)}
                        className="flex items-center gap-2 rounded-md bg-app-surface px-2.5 py-1.5 text-left text-[12px] ring-1 ring-app-line hover:ring-app-accent/50"
                      >
                        <FileGlyph entry={e} size={15} />
                        <span className="truncate">{e.name}</span>
                      </button>
                    );
                  })}
                </div>
              )}
              {m.approval && (
                <div className="mt-2.5 flex items-center gap-2">
                  {m.approval.state === "pending" ? (
                    <>
                      <button type="button" onClick={() => decide(m.id, "approved")} className="rounded-full bg-app-accent px-3.5 py-1.5 text-[12px] font-medium text-white">
                        {t("Approve", "Đồng ý")}
                      </button>
                      <button type="button" onClick={() => decide(m.id, "denied")} className="rounded-full px-3.5 py-1.5 text-[12px] font-medium ring-1 ring-app-line hover:bg-app-hover">
                        {t("Deny", "Từ chối")}
                      </button>
                    </>
                  ) : (
                    <span className="text-[11.5px] text-app-muted">
                      {m.approval.state === "approved" ? t("Approved. Moved to Trash (demo).", "Đã đồng ý. Đã chuyển vào Thùng rác (demo).") : t("Denied. Nothing changed.", "Đã từ chối. Không có gì thay đổi.")}
                    </span>
                  )}
                </div>
              )}
            </div>
          ),
        )}
        {thinking && (
          <div className="inline-flex gap-1 rounded-2xl bg-app-field/80 px-3.5 py-3" aria-label={t("CB Agent is typing", "CB Agent đang trả lời")}>
            {[0, 1, 2].map((i) => (
              <span key={i} className="size-1.5 animate-bounce rounded-full bg-app-muted" style={{ animationDelay: `${i * 120}ms` }} />
            ))}
          </div>
        )}
      </div>

      <div className="shrink-0 p-3 pt-1">
        <div className="mb-2 flex flex-wrap gap-1.5">
          {suggestions.map((s) => (
            <button key={s} type="button" onClick={() => send(s)} className="inline-flex items-center gap-1.5 rounded-full bg-app-field/80 px-2.5 py-1.5 text-[11.5px] hover:bg-app-field">
              <Sparkle size={11} weight="light" className="text-app-accent" />
              {s}
            </button>
          ))}
        </div>
        <form
          onSubmit={(e) => {
            e.preventDefault();
            send(draft);
          }}
          className="rounded-xl bg-app-field/80"
        >
          {folder && (
            <div className="flex items-center gap-1.5 px-3 pt-2 text-[11px] text-app-accent-strong">
              <FolderSimple size={12} />
              <span className="truncate">{folder.name}</span>
            </div>
          )}
          <div className="flex items-end gap-2 p-2 pl-3">
            <label htmlFor="agent-input" className="sr-only">
              {t("Ask AI to find files...", "Hỏi AI để tìm tệp...")}
            </label>
            <input
              id="agent-input"
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              placeholder={t("Ask AI to find files...", "Hỏi AI để tìm tệp...")}
              autoComplete="off"
              className="min-w-0 flex-1 bg-transparent py-1.5 text-[12.5px] outline-none placeholder:text-app-muted"
            />
            <button
              type="submit"
              aria-label={t("Send", "Gửi")}
              disabled={!draft.trim() || thinking}
              className="grid size-8 shrink-0 place-items-center rounded-full bg-app-accent text-white transition disabled:bg-app-muted/25 disabled:text-app-muted"
            >
              <PaperPlaneRight size={14} weight="fill" />
            </button>
          </div>
        </form>
      </div>
    </aside>
  );
}
