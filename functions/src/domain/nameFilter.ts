// Creature name filter (retro C3: names reach friends). Conservative by design:
// letters/digits/space/'-. only, no contact data, no links, small multilingual blocklist.
// Report/block covers whatever slips through.

import { NAME_MAX, NAME_MIN } from "./config.ts";

export type NameVerdict = { ok: true; name: string } | { ok: false; reason: string };

// Stems matched as substrings of the folded name. Kept short and obvious on purpose
// (no short stems like "cock"/"kill" that would hit Peacock/Skillet);
// extend via Remote Config later. (en / uk / ru)
const BLOCKED_STEMS = [
  "fuck", "shit", "bitch", "cunt", "pussy", "whore", "slut", "nigg", "faggot", "rapist",
  "nazi", "hitler", "porn", "penis", "vagina", "suicide",
  "хуй", "хуя", "хує", "пизд", "бля", "єба", "еба", "ёба", "їба", "сука", "мудак", "підор", "пидор", "гандон", "шлюх", "залуп",
];

const LEET: Record<string, string> = { "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b", "@": "a", "$": "s" };

/** Lowercase, strip diacritics, de-leet, drop everything but letters. */
export function fold(s: string): string {
  return s
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/[0-9@$]/g, (c) => LEET[c] ?? c)
    .replace(/[^\p{L}]/gu, "");
}

export function checkName(raw: unknown): NameVerdict {
  if (typeof raw !== "string") return { ok: false, reason: "not-a-string" };
  const name = raw.normalize("NFC").trim().replace(/\s+/g, " ");
  const len = [...name].length;
  if (len < NAME_MIN) return { ok: false, reason: "too-short" };
  if (len > NAME_MAX) return { ok: false, reason: "too-long" };
  if (!/^[\p{L}\p{M}\p{N} '\-.]+$/u.test(name)) return { ok: false, reason: "bad-characters" };
  if (/\p{N}{3,}/u.test(name.replace(/[ \-.]/g, ""))) return { ok: false, reason: "contact-info" };
  if (/(www|http|\.com|\.net|\.org|\.ua|\.ru|t\.me)/i.test(name)) return { ok: false, reason: "link" };
  const folded = fold(name);
  if (BLOCKED_STEMS.some((s) => folded.includes(fold(s)))) return { ok: false, reason: "blocked-word" };
  return { ok: true, name };
}
