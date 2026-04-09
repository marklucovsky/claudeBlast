#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Build an interactive HTML review page for tile image sets.

Usage:
    python3 tools/build_review_page.py --set playful_3d
    python3 tools/build_review_page.py --set high_contrast
    python3 tools/build_review_page.py --set both

Opens in browser automatically. Features:
- Side-by-side current (ARASAAC) vs new tile
- Approve / Reject / Comment per tile
- Filter by category, status, search
- Lightbox zoom on click
- Export reject list as JSON (paste into review_tiles.py reject command)
- State persists in localStorage (survives browser refresh)
"""

import base64
import json
import os
import sys
import webbrowser
from pathlib import Path

VOCAB_FILE = Path("claudeBlast/Resources/vocabulary.json")
ASSETS_DIR = Path("claudeBlast/Assets.xcassets")
OUTPUT_BASE = Path("tools/tile_sets")


def img_to_relative_path(path: Path, html_dir: Path) -> str:
    """Return a relative path from the HTML file's directory to the image."""
    if not path.exists():
        return ""
    try:
        return os.path.relpath(path.resolve(), html_dir.resolve())
    except ValueError:
        return ""


def build_page(set_name: str) -> Path:
    vocab = json.loads(VOCAB_FILE.read_text())
    set_dir = OUTPUT_BASE / set_name
    html_dir = OUTPUT_BASE  # HTML lives in tools/tile_sets/

    # Copy current tiles to a local directory (browser can't follow symlinks/parent paths)
    current_dir = OUTPUT_BASE / "current"
    if not current_dir.exists():
        import shutil
        current_dir.mkdir(parents=True, exist_ok=True)
        for tile in vocab:
            src = ASSETS_DIR / f"{tile['key']}.imageset" / f"{tile['key']}.png"
            if src.exists():
                shutil.copy2(src, current_dir / f"{tile['key']}.png")

    # Load list of tiles modified in the last regeneration pass
    modified_file = OUTPUT_BASE / "last_modified.json"
    modified_keys = set()
    if modified_file.exists():
        modified_keys = set(json.loads(modified_file.read_text()))

    # Build tile data with relative file paths (all within tile_sets/)
    tiles_json = []
    for i, tile in enumerate(vocab):
        key = tile["key"]
        wc = tile.get("wordClass", "unknown")

        current_path = current_dir / f"{key}.png"
        new_path = set_dir / f"{key}.png"

        tiles_json.append({
            "key": key,
            "wordClass": wc,
            "index": i,
            "currentImg": img_to_relative_path(current_path, html_dir),
            "newImg": img_to_relative_path(new_path, html_dir),
            "hasNew": new_path.exists(),
            "modified": key in modified_keys,
        })

    categories = sorted(set(t["wordClass"] for t in tiles_json))

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Blaster Tile Review — {set_name}</title>
<style>
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f7; color: #1d1d1f; }}

.header {{
    position: sticky; top: 0; z-index: 100; background: #fff; border-bottom: 1px solid #ddd;
    padding: 12px 20px; display: flex; flex-wrap: wrap; gap: 10px; align-items: center;
    box-shadow: 0 2px 8px rgba(0,0,0,0.06);
}}
.header h1 {{ font-size: 18px; font-weight: 600; margin-right: 20px; }}
.header select, .header input, .header button {{
    padding: 6px 12px; border: 1px solid #ccc; border-radius: 6px; font-size: 13px;
}}
.header button {{
    background: #007aff; color: white; border: none; cursor: pointer; font-weight: 500;
}}
.header button:hover {{ background: #0066d6; }}
.header button.danger {{ background: #ff3b30; }}
.header button.danger:hover {{ background: #d63028; }}
.header button.success {{ background: #34c759; }}
.stats {{ font-size: 13px; color: #666; margin-left: auto; }}

.grid {{
    display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
    gap: 12px; padding: 16px;
}}

.card {{
    background: #fff; border-radius: 12px; overflow: hidden;
    box-shadow: 0 1px 4px rgba(0,0,0,0.08); transition: box-shadow 0.2s;
}}
.card:hover {{ box-shadow: 0 4px 16px rgba(0,0,0,0.12); }}
.card.approved {{ border-left: 4px solid #34c759; }}
.card.rejected {{ border-left: 4px solid #ff3b30; }}

.card-images {{
    display: flex; gap: 2px; background: #eee; cursor: pointer;
}}
.card-images .img-col {{
    flex: 1; text-align: center; position: relative;
}}
.card-images .img-col img {{
    width: 100%; aspect-ratio: 1; object-fit: cover; display: block;
}}
.card-images .img-label {{ display: none; }}
.card.modified {{ border-top: 3px solid #ff9500; }}
.modified-badge {{
    position: absolute; top: 6px; right: 6px;
    background: #ff9500; color: white; font-size: 9px; font-weight: 600;
    padding: 2px 6px; border-radius: 4px; z-index: 1;
}}

.progress-bar {{
    height: 4px; background: #e5e5e5; border-radius: 2px; overflow: hidden; flex: 1; min-width: 100px;
}}
.progress-bar .fill {{
    height: 100%; border-radius: 2px; transition: width 0.3s;
    background: linear-gradient(90deg, #34c759, #007aff);
}}

.card-body {{ padding: 10px 12px; }}
.card-body .tile-key {{ font-weight: 600; font-size: 14px; }}
.card-body .tile-class {{ font-size: 12px; color: #888; margin-left: 6px; }}
.card-actions {{ display: flex; gap: 6px; margin-top: 8px; align-items: center; }}
.card-actions button {{
    padding: 4px 10px; border: 1px solid #ddd; border-radius: 6px; font-size: 12px;
    cursor: pointer; background: #f9f9f9;
}}
.card-actions button:hover {{ background: #eee; }}
.card-actions button.active-approve {{ background: #34c759; color: white; border-color: #34c759; }}
.card-actions button.active-reject {{ background: #ff3b30; color: white; border-color: #ff3b30; }}
.card-actions input {{
    flex: 1; padding: 4px 8px; border: 1px solid #ddd; border-radius: 6px; font-size: 12px;
}}

/* Lightbox */
.lightbox {{
    display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%;
    background: rgba(0,0,0,0.85); z-index: 200; justify-content: center; align-items: center;
    gap: 20px; padding: 40px;
}}
.lightbox.active {{ display: flex; }}
.lightbox img {{ max-height: 80vh; max-width: 45vw; border-radius: 8px; }}
.lightbox .label {{
    position: absolute; bottom: 40px; color: white; font-size: 16px; font-weight: 500;
}}
.lightbox .close {{
    position: absolute; top: 20px; right: 30px; color: white; font-size: 32px;
    cursor: pointer; line-height: 1;
}}

.hidden {{ display: none !important; }}
</style>
</head>
<body>

<div class="header">
    <h1>Tile Review: {set_name}</h1>
    <select id="filterCategory">
        <option value="all">All Categories</option>
        {"".join(f'<option value="{c}">{c}</option>' for c in categories)}
    </select>
    <select id="filterStatus">
        <option value="all">All Status</option>
        <option value="unreviewed">Unreviewed</option>
        <option value="approved">Approved</option>
        <option value="rejected">Rejected</option>
        <option value="modified">Modified (this pass)</option>
    </select>
    <input type="text" id="searchBox" placeholder="Search tiles..." />
    <button class="success" onclick="approveAll()">Approve All Visible</button>
    <button class="danger" onclick="exportRejects()">Export Rejects</button>
    <button onclick="exportAll()">Export Full Review</button>
    <div class="progress-bar"><div class="fill" id="progressFill"></div></div>
    <div class="stats" id="stats"></div>
</div>

<div class="grid" id="grid"></div>

<div class="lightbox" id="lightbox" onclick="closeLightbox()">
    <span class="close">&times;</span>
    <img id="lb-current" />
    <img id="lb-new" />
</div>

<script>
const SET_NAME = "{set_name}";
const TILES = {json.dumps(tiles_json)};
const STORAGE_KEY = "blaster_review_" + SET_NAME;

// Load state from localStorage
let state = {{}};
try {{ state = JSON.parse(localStorage.getItem(STORAGE_KEY)) || {{}}; }} catch(e) {{}}

function saveState() {{
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}}

function getState(key) {{
    return state[key] || {{ status: "unreviewed", comment: "" }};
}}

function setState(key, updates) {{
    state[key] = {{ ...getState(key), ...updates }};
    saveState();
    renderCard(key);
    updateStats();
}}

function renderCard(key) {{
    const el = document.getElementById("card-" + key);
    if (!el) return;
    const s = getState(key);
    el.className = "card " + s.status;
    const approveBtn = el.querySelector(".btn-approve");
    const rejectBtn = el.querySelector(".btn-reject");
    const commentInput = el.querySelector(".comment-input");
    approveBtn.className = s.status === "approved" ? "btn-approve active-approve" : "btn-approve";
    rejectBtn.className = s.status === "rejected" ? "btn-reject active-reject" : "btn-reject";
    commentInput.value = s.comment || "";
}}

function updateStats() {{
    const total = TILES.length;
    let approved = 0, rejected = 0;
    TILES.forEach(t => {{
        const s = getState(t.key);
        if (s.status === "approved") approved++;
        if (s.status === "rejected") rejected++;
    }});
    const reviewed = approved + rejected;
    const pct = Math.round(reviewed / total * 100);
    document.getElementById("stats").textContent =
        `${{pct}}% reviewed (${{approved}} ok / ${{rejected}} redo / ${{total - reviewed}} left)`;
    document.getElementById("progressFill").style.width = pct + "%";
}}

function buildGrid() {{
    const grid = document.getElementById("grid");
    grid.innerHTML = "";
    TILES.forEach(t => {{
        const s = getState(t.key);
        const card = document.createElement("div");
        card.id = "card-" + t.key;
        card.className = "card " + s.status + (t.modified ? " modified" : "");
        card.dataset.key = t.key;
        card.dataset.wordclass = t.wordClass;
        card.dataset.modified = t.modified ? "true" : "false";

        card.innerHTML = `
            <div class="card-images" onclick="openLightbox('${{t.key}}')" style="position:relative">
                ${{t.modified ? '<span class="modified-badge">UPDATED</span>' : ''}}
                <div class="img-col">
                    ${{t.currentImg ? `<img src="${{t.currentImg}}" loading="lazy" />` : '<div style="aspect-ratio:1;background:#eee;display:flex;align-items:center;justify-content:center;color:#999">No current</div>'}}
                    <span class="img-label">Current</span>
                </div>
                <div class="img-col">
                    ${{t.newImg ? `<img src="${{t.newImg}}" loading="lazy" />` : '<div style="aspect-ratio:1;background:#eee;display:flex;align-items:center;justify-content:center;color:#999">Missing</div>'}}
                    <span class="img-label">${{SET_NAME}}</span>
                </div>
            </div>
            <div class="card-body">
                <span class="tile-key">${{t.key}}</span>
                <span class="tile-class">${{t.wordClass}}</span>
                <div class="card-actions">
                    <button class="btn-approve ${{s.status === 'approved' ? 'active-approve' : ''}}"
                            onclick="setState('${{t.key}}', {{status: getState('${{t.key}}').status === 'approved' ? 'unreviewed' : 'approved'}})">&#10003;</button>
                    <button class="btn-reject ${{s.status === 'rejected' ? 'active-reject' : ''}}"
                            onclick="setState('${{t.key}}', {{status: getState('${{t.key}}').status === 'rejected' ? 'unreviewed' : 'rejected'}})">&#10007;</button>
                    <div style="position:relative;flex:1">
                        <input class="comment-input" type="text" placeholder="Comment..." style="width:100%;padding-right:24px"
                               value="${{(s.comment || '').replace(/"/g, '&quot;')}}"
                               onchange="setState('${{t.key}}', {{comment: this.value}})" />
                        <span onclick="this.previousElementSibling.value='';setState('${{t.key}}',{{comment:''}})"
                              style="position:absolute;right:6px;top:50%;transform:translateY(-50%);cursor:pointer;color:#999;font-size:14px;line-height:1">&times;</span>
                    </div>
                </div>
            </div>
        `;
        grid.appendChild(card);
    }});
    updateStats();
}}

function applyFilters() {{
    const cat = document.getElementById("filterCategory").value;
    const status = document.getElementById("filterStatus").value;
    const search = document.getElementById("searchBox").value.toLowerCase();

    document.querySelectorAll(".card").forEach(card => {{
        const key = card.dataset.key;
        const wc = card.dataset.wordclass;
        const s = getState(key);
        let show = true;
        if (cat !== "all" && wc !== cat) show = false;
        if (status === "modified") {{
            if (card.dataset.modified !== "true") show = false;
        }} else if (status !== "all" && s.status !== status) show = false;
        if (search && !key.includes(search)) show = false;
        card.classList.toggle("hidden", !show);
    }});
}}

function approveAll() {{
    document.querySelectorAll(".card:not(.hidden)").forEach(card => {{
        const key = card.dataset.key;
        if (getState(key).status === "unreviewed") {{
            setState(key, {{ status: "approved" }});
        }}
    }});
}}

function exportRejects() {{
    const rejects = {{}};
    TILES.forEach(t => {{
        const s = getState(t.key);
        if (s.status === "rejected") {{
            rejects[t.key] = {{ reason: s.comment || "rejected in review", attempts: 1 }};
        }}
    }});
    const keys = Object.keys(rejects);
    if (keys.length === 0) {{ alert("No rejected tiles!"); return; }}

    const jsonText = JSON.stringify(rejects, null, 2);
    navigator.clipboard.writeText(jsonText).then(() => {{
        alert(`${{keys.length}} rejected tiles copied to clipboard as JSON. Paste to Claude.`);
    }}).catch(() => {{
        // Fallback: open in a new window so user can copy
        const w = window.open("", "_blank");
        w.document.write("<pre>" + jsonText + "</pre>");
    }});
}}

function exportAll() {{
    const review = {{}};
    TILES.forEach(t => {{
        review[t.key] = getState(t.key);
    }});
    const blob = new Blob([JSON.stringify(review, null, 2)], {{type: "application/json"}});
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `review_${{SET_NAME}}.json`;
    a.click();
}}

// Lightbox
const tileMap = {{}};
TILES.forEach(t => tileMap[t.key] = t);

function openLightbox(key) {{
    const t = tileMap[key];
    document.getElementById("lb-current").src = t.currentImg || "";
    document.getElementById("lb-new").src = t.newImg || "";
    document.getElementById("lightbox").classList.add("active");
}}
function closeLightbox() {{
    document.getElementById("lightbox").classList.remove("active");
}}
document.addEventListener("keydown", e => {{
    if (e.key === "Escape") closeLightbox();
}});

// Init
document.getElementById("filterCategory").addEventListener("change", applyFilters);
document.getElementById("filterStatus").addEventListener("change", applyFilters);
document.getElementById("searchBox").addEventListener("input", applyFilters);
buildGrid();
</script>
</body>
</html>"""

    out_path = OUTPUT_BASE / f"review_{set_name}.html"
    out_path.write_text(html)
    print(f"Review page: {out_path} ({len(html) // 1024} KB)")
    return out_path


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--set", required=True, choices=["playful_3d", "high_contrast", "both"])
    args = parser.parse_args()

    sets = ["playful_3d", "high_contrast"] if args.set == "both" else [args.set]
    for s in sets:
        print(f"\nBuilding review page for {s}...")
        path = build_page(s)
        webbrowser.open(f"file://{path.resolve()}")


if __name__ == "__main__":
    main()
