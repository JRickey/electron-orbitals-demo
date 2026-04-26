// extension.js — HolyC VSCode extension entry point.
//
// Surfaces scripts/holyc-lint.py output as inline diagnostics. The
// extension activates when a HolyC document opens, lints on open and on
// save, and runs the linter as a subprocess so we share exactly one
// rule set with `make lint` (no JS reimplementation to drift).
//
// No npm dependencies. The `vscode` module is injected by the host at
// runtime; node_modules is not required.

const vscode = require("vscode");
const cp = require("node:child_process");
const path = require("node:path");
const fs = require("node:fs");

let collection;

// path:line:col: level: message  [rule]
const DIAG_RE = /^(.+?):(\d+):(\d+):\s+(error|warning):\s+(.+?)\s+\[([^\]]+)\]\s*$/;

function activate(context) {
  collection = vscode.languages.createDiagnosticCollection("holyc");
  context.subscriptions.push(collection);

  // Lint any HolyC docs already open at activation.
  for (const doc of vscode.workspace.textDocuments) {
    if (doc.languageId === "holyc") lint(doc);
  }

  context.subscriptions.push(
    vscode.workspace.onDidOpenTextDocument((doc) => {
      if (doc.languageId === "holyc") lint(doc);
    }),
    vscode.workspace.onDidSaveTextDocument((doc) => {
      if (doc.languageId === "holyc") lint(doc);
    }),
    vscode.workspace.onDidCloseTextDocument((doc) => {
      collection.delete(doc.uri);
    }),
  );
}

function deactivate() {
  if (collection) collection.dispose();
}

function lint(doc) {
  const ws = vscode.workspace.getWorkspaceFolder(doc.uri);
  if (!ws) return; // unsaved / outside any workspace
  const root = ws.uri.fsPath;
  const cfg = vscode.workspace.getConfiguration("holyc", doc.uri);
  const py = cfg.get("pythonPath") || "python3";
  const script = cfg.get("lintScript") || "scripts/holyc-lint.py";
  const scriptAbs = path.isAbsolute(script) ? script : path.join(root, script);

  if (!fs.existsSync(scriptAbs)) {
    // Script not present in this workspace — silent. Don't spam users
    // who installed the extension for the highlighting alone.
    collection.set(doc.uri, []);
    return;
  }

  const proc = cp.spawn(py, [scriptAbs, doc.uri.fsPath], {
    cwd: root,
    env: { ...process.env, NO_COLOR: "1" },
  });
  let stdout = "";
  let stderr = "";
  proc.stdout.on("data", (chunk) => (stdout += chunk));
  proc.stderr.on("data", (chunk) => (stderr += chunk));
  proc.on("error", (err) => {
    vscode.window.showErrorMessage(`holyc-lint: ${err.message}`);
  });
  proc.on("close", () => {
    const diagnostics = [];
    for (const ln of stdout.split("\n")) {
      const m = DIAG_RE.exec(ln);
      if (!m) continue;
      const [, , lineStr, colStr, level, msg, rule] = m;
      const line = Math.max(0, parseInt(lineStr, 10) - 1);
      const col = Math.max(0, parseInt(colStr, 10) - 1);
      const range = wordRangeAt(doc, line, col);
      const d = new vscode.Diagnostic(
        range,
        msg,
        level === "error"
          ? vscode.DiagnosticSeverity.Error
          : vscode.DiagnosticSeverity.Warning,
      );
      d.source = "holyc-lint";
      d.code = rule;
      diagnostics.push(d);
    }
    collection.set(doc.uri, diagnostics);
  });
}

function wordRangeAt(doc, line, col) {
  if (line >= doc.lineCount) {
    return new vscode.Range(line, col, line, col + 1);
  }
  const pos = new vscode.Position(line, col);
  const wr = doc.getWordRangeAtPosition(pos);
  if (wr) return wr;
  const lineLen = doc.lineAt(line).text.length;
  const end = Math.min(lineLen, col + 1);
  return new vscode.Range(line, col, line, Math.max(end, col + 1));
}

module.exports = { activate, deactivate };
