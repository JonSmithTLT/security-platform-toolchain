#!/usr/bin/env bash
# Offline npm install and import smoke for spt-frontend-node-toolchain.

set -euo pipefail
umask 0000

REGISTRY="${1:-${REGISTRY:-registry.internal/security-platform}}"
TAG="${2:-${TAG:-latest}}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${ROOT_DIR}/artifacts/frontend-npm-smoke"
IMAGE="${REGISTRY}/spt-frontend-node-toolchain:${TAG}"

fail() { printf 'frontend-npm-smoke failed: %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

printf '==> Running offline frontend npm smoke against %s\n' "${IMAGE}"

docker run --rm --network none \
    -v "${OUT_DIR}:/out" \
    "${IMAGE}" \
    bash -lc '
        set -euo pipefail
        cp /opt/spt-frontend/package/package.json /out/package.json
        cp /opt/spt-frontend/package/package-lock.json /out/package-lock.json
        cd /out
        npm ci --offline --ignore-scripts --cache /opt/spt-frontend/npm-cache
        node --input-type=module - <<'"'"'NODEEOF'"'"'
import React from "react";
import { createRoot } from "react-dom/client";
import { QueryClient } from "@tanstack/react-query";
import { z } from "zod";
import { clsx } from "clsx";
import { twMerge } from "tailwind-merge";
import { cva } from "class-variance-authority";
import { Search } from "lucide-react";
import { create } from "zustand";
import { nanoid } from "nanoid";
import { formatISO } from "date-fns";
import yaml from "yaml";
import Papa from "papaparse";
import ResizablePanels from "react-resizable-panels";
import { Command } from "cmdk";
import { toast } from "sonner";
import { flexRender } from "@tanstack/react-table";
import { useVirtualizer } from "@tanstack/react-virtual";
import { Background } from "@xyflow/react";
import dagre from "dagre";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import rehypeSanitize from "rehype-sanitize";
import Prism from "prismjs";
import { JsonView } from "react-json-view-lite";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import * as Dialog from "@radix-ui/react-dialog";
import * as AlertDialog from "@radix-ui/react-alert-dialog";
import * as Progress from "@radix-ui/react-progress";
import * as Tooltip from "@radix-ui/react-tooltip";
import * as Toast from "@radix-ui/react-toast";

const schema = z.object({ name: z.string() });
schema.parse({ name: "revelations" });
new QueryClient();
create(() => ({ selected: nanoid() }));
clsx("a", { b: true });
twMerge("p-2 p-4");
cva("rounded")();
formatISO(new Date(0));
yaml.parse("a: 1");
Papa.parse("a,b\n1,2");
dagre.graphlib.Graph;
React.createElement(Search);
React.createElement(Command);
React.createElement(ResizablePanels.PanelGroup, { direction: "horizontal" });
React.createElement(ReactMarkdown, { remarkPlugins: [remarkGfm], rehypePlugins: [rehypeSanitize] });
React.createElement(JsonView, { data: { ok: true } });
React.createElement(Dialog.Root);
React.createElement(AlertDialog.Root);
React.createElement(Progress.Root);
React.createElement(Tooltip.Provider);
React.createElement(Toast.Provider);
void createRoot;
void flexRender;
void useVirtualizer;
void Background;
void Prism;
void useForm;
void zodResolver;
void toast;
console.log("frontend npm imports OK");
NODEEOF
        mkdir -p src
        cat > index.html <<'"'"'HTMLEOF'"'"'
<div id="root"></div>
<script type="module" src="/src/main.jsx"></script>
HTMLEOF
        cat > src/main.jsx <<'"'"'JSEOF'"'"'
import React from "react";
import { createRoot } from "react-dom/client";
import { QueryClient } from "@tanstack/react-query";
import { z } from "zod";
import { clsx } from "clsx";
import { Search } from "lucide-react";

const schema = z.object({ status: z.literal("ready") });
schema.parse({ status: "ready" });
new QueryClient();

function App() {
  return React.createElement(
    "main",
    { className: clsx("app-shell") },
    React.createElement(Search, { size: 16 }),
    React.createElement("span", null, "REVELATIONS offline build smoke")
  );
}

createRoot(document.getElementById("root")).render(React.createElement(App));
JSEOF
        npm run build --offline --ignore-scripts --cache /opt/spt-frontend/npm-cache
    ' || fail "offline npm install/import smoke failed"

pass "frontend npm offline install/import/build smoke"
