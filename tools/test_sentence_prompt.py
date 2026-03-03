#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
claudeBlast Sentence Prompt Tester

Compare how gpt-4o-mini vs gpt-audio-mini respond to the same tile selection.
Useful for detecting narrator/third-person drift in the audio model and for
iterating on prompt wording without rebuilding the app.

Usage:
    export OPENAI_API_KEY=sk-...
    python3 tools/test_sentence_prompt.py --tiles grandpa playground
    python3 tools/test_sentence_prompt.py --tiles mom hungry milk --grade 3 --text-only
    python3 tools/test_sentence_prompt.py --tiles eat grandpa --audio-only --passes 5
    python3 tools/test_sentence_prompt.py --tiles grandpa playground --history "Can we go outside?" --passes 2

Arguments:
    --tiles KEY [KEY ...]    required; tile keys looked up in vocabulary.json
    --passes N               generation passes per model (default: 3)
    --grade N                grade level 1-8 (default: 2)
    --text-only              only call gpt-4o-mini
    --audio-only             only call gpt-audio-mini
    --history S [S ...]      prior sentences to inject as conversation history

IMPORTANT: Never commit API keys. Always pass via OPENAI_API_KEY env var.
"""

import argparse
import json
import os
import ssl
import sys
import urllib.request
import urllib.error
from pathlib import Path

# macOS: Python's bundled OpenSSL can't find system root certs.
# This is a local dev tool — disable cert verification rather than require pip installs.
_ssl_ctx = ssl.create_default_context()
_ssl_ctx.check_hostname = False
_ssl_ctx.verify_mode = ssl.CERT_NONE

CHAT_URL = "https://api.openai.com/v1/chat/completions"
TEXT_MODEL = "gpt-4o-mini"
AUDIO_MODEL = "gpt-audio-mini"

VOCAB_FILE = Path(__file__).parent.parent / "claudeBlast" / "Resources" / "vocabulary.json"
PROMPT_FILE = Path(__file__).parent.parent / "claudeBlast" / "Resources" / "sentence_prompt.json"

WIDTH = 70


def grade_description(grade: int) -> str:
    if grade == 1:
        return "1st-grade"
    elif grade == 2:
        return "2nd-grade"
    elif grade == 3:
        return "3rd-grade"
    else:
        return f"{grade}th-grade"


def load_vocabulary() -> dict[str, str]:
    """Return {key: wordClass} for all vocabulary entries."""
    with open(VOCAB_FILE, encoding="utf-8") as f:
        entries = json.load(f)
    return {e["key"]: e.get("wordClass", "unknown") for e in entries}


def load_system_messages(grade_str: str) -> list[str]:
    """Load sentence_prompt.json and substitute {grade} placeholder."""
    with open(PROMPT_FILE, encoding="utf-8") as f:
        messages = json.load(f)
    return [m.replace("{grade}", grade_str) for m in messages]


def build_messages(
    system_messages: list[str],
    user_prompt: str,
    history: list[str],
) -> list[dict]:
    msgs = [{"role": "system", "content": m} for m in system_messages]
    for sentence in history:
        msgs.append({"role": "assistant", "content": sentence})
    msgs.append({"role": "user", "content": user_prompt})
    return msgs


def call_api(payload: dict, api_key: str) -> dict:
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        CHAT_URL,
        data=body,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, context=_ssl_ctx) as resp:
        return json.loads(resp.read())


def call_text_model(messages: list[dict], api_key: str) -> tuple[str, int, int]:
    """Returns (text, prompt_tokens, completion_tokens)."""
    payload = {
        "model": TEXT_MODEL,
        "messages": messages,
        "max_tokens": 500,
    }
    data = call_api(payload, api_key)
    text = data["choices"][0]["message"]["content"].strip()
    usage = data.get("usage", {})
    return text, usage.get("prompt_tokens", 0), usage.get("completion_tokens", 0)


def call_audio_model(messages: list[dict], api_key: str) -> tuple[str, int, int, int]:
    """Returns (transcript, prompt_tokens, text_completion_tokens, audio_completion_tokens)."""
    payload = {
        "model": AUDIO_MODEL,
        "modalities": ["text", "audio"],
        "audio": {"voice": "nova", "format": "mp3"},
        "messages": messages,
        "max_tokens": 10000,
    }
    data = call_api(payload, api_key)
    choice = data["choices"][0]["message"]
    # Audio model returns transcript in audio field
    if "audio" in choice and choice["audio"]:
        transcript = choice["audio"].get("transcript", "").strip()
    else:
        # Fallback: some responses may include text content directly
        transcript = choice.get("content", "").strip() or "(no transcript)"

    usage = data.get("usage", {})
    prompt_tokens = usage.get("prompt_tokens", 0)
    completion_details = usage.get("completion_tokens_details", {})
    text_tokens = completion_details.get("text_tokens", 0)
    audio_tokens = completion_details.get("audio_tokens", 0)
    # Fallback if details not present
    if text_tokens == 0 and audio_tokens == 0:
        total = usage.get("completion_tokens", 0)
        text_tokens = total
    return transcript, prompt_tokens, text_tokens, audio_tokens


def separator(char="─", label="", width=WIDTH) -> str:
    if label:
        pad = (width - len(label) - 2) // 2
        return char * pad + f" {label} " + char * (width - pad - len(label) - 2)
    return char * width


def main():
    parser = argparse.ArgumentParser(
        description="claudeBlast sentence prompt tester",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--tiles", nargs="+", required=True, metavar="KEY",
                        help="Tile keys (e.g. grandpa playground)")
    parser.add_argument("--passes", type=int, default=3, metavar="N",
                        help="Number of generation passes per model (default: 3)")
    parser.add_argument("--grade", type=int, default=2, metavar="N",
                        help="Grade level 1-8 (default: 2)")
    parser.add_argument("--text-only", action="store_true",
                        help="Only call gpt-4o-mini")
    parser.add_argument("--audio-only", action="store_true",
                        help="Only call gpt-audio-mini")
    parser.add_argument("--history", nargs="+", metavar="S", default=[],
                        help="Prior sentences to inject as conversation history")
    args = parser.parse_args()

    if args.text_only and args.audio_only:
        sys.exit("Error: --text-only and --audio-only are mutually exclusive.")

    api_key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not api_key:
        sys.exit(
            "Error: OPENAI_API_KEY environment variable is not set.\n"
            "  export OPENAI_API_KEY=sk-..."
        )

    # Load vocabulary
    try:
        vocab = load_vocabulary()
    except FileNotFoundError:
        sys.exit(f"Error: vocabulary.json not found at {VOCAB_FILE}")

    # Resolve tile keys → (value, wordClass)
    tiles: list[tuple[str, str]] = []
    for key in args.tiles:
        word_class = vocab.get(key)
        if word_class is None:
            print(f"Warning: tile key '{key}' not found in vocabulary.json — using 'unknown'",
                  file=sys.stderr)
            word_class = "unknown"
        value = key.replace("_", " ")
        tiles.append((value, word_class))

    user_prompt = ", ".join(f"{v} ({wc})" for v, wc in tiles)
    grade_str = grade_description(args.grade)

    # Load system messages
    try:
        system_messages = load_system_messages(grade_str)
    except FileNotFoundError:
        sys.exit(f"Error: sentence_prompt.json not found at {PROMPT_FILE}")

    # Print header
    print("═" * WIDTH)
    print("claudeBlast Sentence Prompt Tester".center(WIDTH))
    print("═" * WIDTH)
    print(f"Tiles : {user_prompt}")
    print(f"Grade : {grade_str}  |  Passes: {args.passes}")
    if args.history:
        print(f"History: {' | '.join(args.history)}")
    print()

    # Stats accumulators: {model: {"prompt": [], "completion": []}}
    stats: dict[str, dict] = {
        TEXT_MODEL: {"prompt": [], "completion": []},
        AUDIO_MODEL: {"prompt": [], "completion_text": [], "completion_audio": []},
    }

    messages_base = build_messages(system_messages, user_prompt, args.history)

    for pass_num in range(1, args.passes + 1):
        print(separator("─", f"PASS {pass_num}"))

        if not args.audio_only:
            try:
                text, pt, ct = call_text_model(messages_base, api_key)
                print(f"[{TEXT_MODEL}]")
                print(f'  "{text}"')
                print(f"  tokens: {pt} prompt / {ct} completion")
                stats[TEXT_MODEL]["prompt"].append(pt)
                stats[TEXT_MODEL]["completion"].append(ct)
            except urllib.error.HTTPError as e:
                body = e.read().decode("utf-8", errors="replace")
                print(f"[{TEXT_MODEL}] HTTP {e.code}: {body[:200]}")
            except Exception as e:
                print(f"[{TEXT_MODEL}] Error: {e}")
            print()

        if not args.text_only:
            try:
                transcript, pt, ct_text, ct_audio = call_audio_model(messages_base, api_key)
                print(f"[{AUDIO_MODEL}]")
                print(f'  "{transcript}"')
                print(f"  tokens: {pt} prompt / {ct_text} text + {ct_audio} audio completion")
                stats[AUDIO_MODEL]["prompt"].append(pt)
                stats[AUDIO_MODEL]["completion_text"].append(ct_text)
                stats[AUDIO_MODEL]["completion_audio"].append(ct_audio)
            except urllib.error.HTTPError as e:
                body = e.read().decode("utf-8", errors="replace")
                print(f"[{AUDIO_MODEL}] HTTP {e.code}: {body[:200]}")
            except Exception as e:
                print(f"[{AUDIO_MODEL}] Error: {e}")
            print()

    # Summary
    print(separator("═"))
    print("SUMMARY".center(WIDTH))
    print(separator("─"))

    if not args.audio_only and stats[TEXT_MODEL]["prompt"]:
        pts = stats[TEXT_MODEL]["prompt"]
        cts = stats[TEXT_MODEL]["completion"]
        avg_pt = sum(pts) / len(pts)
        avg_ct = sum(cts) / len(cts)
        print(f"[{TEXT_MODEL}]  avg prompt: {avg_pt:.0f}  avg completion: {avg_ct:.0f}")

    if not args.text_only and stats[AUDIO_MODEL]["prompt"]:
        pts = stats[AUDIO_MODEL]["prompt"]
        cts_t = stats[AUDIO_MODEL]["completion_text"]
        cts_a = stats[AUDIO_MODEL]["completion_audio"]
        avg_pt = sum(pts) / len(pts)
        avg_ct_t = sum(cts_t) / len(cts_t)
        avg_ct_a = sum(cts_a) / len(cts_a)
        print(
            f"[{AUDIO_MODEL}]  avg prompt: {avg_pt:.0f}  "
            f"avg completion: {avg_ct_t:.0f} text + {avg_ct_a:.0f} audio"
        )

    print(separator("═"))


if __name__ == "__main__":
    main()
