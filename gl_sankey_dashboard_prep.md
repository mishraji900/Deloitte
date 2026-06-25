// filename: main.js
const { app, BrowserWindow, ipcMain, dialog, shell } = require("electron");
const path = require("path");
const fs = require("fs");
const { spawn, execFileSync } = require("child_process");
const axios = require("axios");

const FLASK_BASE_URL = "http://127.0.0.1:5123";
const FLASK_HEALTH_RETRIES = 30;
const FLASK_HEALTH_DELAY_MS = 300;

let mainWindow = null;
let flaskProcess = null;
let flaskReady = false;
let workspaceDir = null;
let convertedDir = null;
let reportDir = null;

// ---------- window ----------

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1400,
    height: 900,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  if (app.isPackaged) {
    mainWindow.loadFile(path.join(__dirname, "dist-renderer", "index.html"));
  } else {
    mainWindow.loadURL("http://localhost:5173");
  }
}

// ---------- workspace (task 1 + task 2, now triggered from Upload screen button) ----------

function hideFolderWindows(folderPath) {
  if (process.platform !== "win32") return;
  try {
    execFileSync("attrib", ["+h", folderPath]);
  } catch (error) {
    console.error(`Failed to hide folder: ${error.message}`);
  }
}

function setupWorkspace(selectedDir) {
  workspaceDir = selectedDir;
  convertedDir = path.join(workspaceDir, "converted");
  reportDir = path.join(workspaceDir, "output", "validation_control_totals");

  fs.mkdirSync(convertedDir, { recursive: true });
  fs.mkdirSync(reportDir, { recursive: true });
  hideFolderWindows(convertedDir);
}

// ---------- flask backend (convert / sheets / preview) ----------

function getFlaskLaunchConfig() {
  if (app.isPackaged) {
    return {
      command: path.join(process.resourcesPath, "backend", "app.exe"),
      args: [],
      cwd: path.join(process.resourcesPath, "backend")
    };
  }

  return {
    command: process.platform === "win32" ? "python" : "python3",
    args: [path.join(__dirname, "python_backend", "app.py")],
    cwd: path.join(__dirname, "python_backend")
  };
}

function startFlaskBackend() {
  if (flaskProcess) return; // already running, don't double-spawn

  const cfg = getFlaskLaunchConfig();

  flaskProcess = spawn(cfg.command, cfg.args, {
    cwd: cfg.cwd,
    windowsHide: true,
    env: { ...process.env, CONVERTED_DIR: convertedDir }
  });

  flaskProcess.stdout.on("data", (data) => {
    console.log(`[flask] ${data.toString().trim()}`);
  });

  flaskProcess.stderr.on("data", (data) => {
    console.error(`[flask] ${data.toString().trim()}`);
  });

  flaskProcess.on("error", (error) => {
    console.error(`Failed to start Flask backend: ${error.message}`);
  });

  flaskProcess.on("close", (code) => {
    console.log(`Flask backend exited with code ${code}`);
    flaskProcess = null;
    flaskReady = false;
  });
}

async function waitForFlaskReady() {
  for (let attempt = 0; attempt < FLASK_HEALTH_RETRIES; attempt++) {
    try {
      await axios.get(`${FLASK_BASE_URL}/health`, { timeout: 1000 });
      flaskReady = true;
      return true;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, FLASK_HEALTH_DELAY_MS));
    }
  }
  return false;
}

function stopFlaskBackend() {
  if (flaskProcess && !flaskProcess.killed) {
    flaskProcess.kill();
    flaskProcess = null;
    flaskReady = false;
  }
}

// ---------- validation backend (stdin/stdout, one-shot per run) ----------

function getPythonScriptConfig(devScriptName, packagedExeName) {
  if (app.isPackaged) {
    return {
      command: path.join(process.resourcesPath, "backend", packagedExeName),
      args: []
    };
  }

  return {
    command: process.platform === "win32" ? "python" : "python3",
    args: [path.join(__dirname, "python_backend", devScriptName)]
  };
}

function runPythonStdinJson(cfg, payload) {
  return new Promise((resolve, reject) => {
    const child = spawn(cfg.command, cfg.args, {
      stdio: ["pipe", "pipe", "pipe"],
      windowsHide: true
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (data) => {
      stdout += data.toString();
    });

    child.stderr.on("data", (data) => {
      stderr += data.toString();
    });

    child.on("error", (error) => {
      reject(new Error(`Failed to start ${cfg.args[0] || "script"}: ${error.message}`));
    });

    child.on("close", (code) => {
      if (!stdout.trim()) {
        reject(new Error(stderr || `Process exited with code ${code}`));
        return;
      }

      try {
        resolve(JSON.parse(stdout));
      } catch {
        reject(new Error(`Invalid JSON from process.\n${stdout}\n${stderr}`));
      }
    });

    child.stdin.write(JSON.stringify(payload));
    child.stdin.end();
  });
}

// ---------- IPC handlers ----------

ipcMain.handle("select-workspace-dir", async () => {
  const result = await dialog.showOpenDialog({
    title: "Choose a workspace folder",
    properties: ["openDirectory", "createDirectory"]
  });

  if (result.canceled || !result.filePaths.length) {
    return { workspaceDir: null, convertedDir: null, ready: false };
  }

  setupWorkspace(result.filePaths[0]);

  startFlaskBackend();
  const ready = await waitForFlaskReady();

  return { workspaceDir, convertedDir, reportDir, ready };
});

ipcMain.handle("get-workspace-dir", async () => {
  return { workspaceDir, convertedDir, reportDir, ready: flaskReady };
});

ipcMain.handle("select-files", async () => {
  const result = await dialog.showOpenDialog({
    properties: ["openFile", "multiSelections"],
    filters: [
      { name: "Excel Files", extensions: ["xls", "xlsx", "xlsm"] },
      { name: "All Files", extensions: ["*"] }
    ]
  });

  if (result.canceled || !result.filePaths.length) {
    return [];
  }

  return result.filePaths;
});

ipcMain.handle("convert-files", async (_event, filePaths) => {
  if (!flaskReady) {
    return { error: "Select a workspace folder first." };
  }
  const response = await axios.post(`${FLASK_BASE_URL}/convert`, { files: filePaths });
  return response.data;
});

ipcMain.handle("get-sheets", async (_event, filePath) => {
  if (!flaskReady) {
    return { error: "Select a workspace folder first." };
  }
  try {
    const response = await axios.post(`${FLASK_BASE_URL}/sheets`, { file: filePath });
    return response.data;
  } catch (error) {
    const message = error.response?.data?.error || error.message;
    return { error: message };
  }
});

ipcMain.handle("preview-sheet", async (_event, filePath, sheetName) => {
  if (!flaskReady) {
    return { error: "Select a workspace folder first." };
  }
  try {
    const response = await axios.post(`${FLASK_BASE_URL}/preview`, {
      file: filePath,
      sheet: sheetName
    });
    return response.data;
  } catch (error) {
    const message = error.response?.data?.error || error.message;
    return { error: message };
  }
});

ipcMain.handle("run-validation", async (_event, payload) => {
  if (!convertedDir || !reportDir) {
    return { success: false, overallStatus: "FAIL", message: "Select a workspace folder first.", files: [] };
  }
  // task 3: hidden converted/ folder for validated-range output (on overall PASS)
  // report always goes to workspace/output/validation_control_totals — not user-configurable.
  const fullPayload = { ...payload, converted_dir: convertedDir, report_output_dir: reportDir };
  return runPythonStdinJson(getPythonScriptConfig("excel_validation.py", "excel_validation.exe"), fullPayload);
});

ipcMain.handle("select-template-file", async () => {
  const result = await dialog.showOpenDialog({
    title: "Choose the trial balance template workbook",
    properties: ["openFile"],
    filters: [{ name: "Excel Workbook", extensions: ["xlsx", "xlsm"] }]
  });

  if (result.canceled || !result.filePaths.length) {
    return null;
  }

  return result.filePaths[0];
});

ipcMain.handle("run-trial-balance", async (_event, payload) => {
  if (!workspaceDir) {
    return { success: false, message: "Select a workspace folder first.", log: [] };
  }

  const outputPath = path.join(workspaceDir, "output", "trial_balance.xlsx");
  const fullPayload = { ...payload, output_path: outputPath };
  return runPythonStdinJson(getPythonScriptConfig("trial_balance.py", "trial_balance.exe"), fullPayload);
});

ipcMain.handle("open-report", async (_event, reportPath) => {
  if (!reportPath) return false;
  const result = await shell.openPath(reportPath);
  return result === "";
});

// ---------- lifecycle ----------

app.whenReady().then(() => {
  createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on("window-all-closed", () => {
  stopFlaskBackend();
  if (process.platform !== "darwin") {
    app.quit();
  }
});

app.on("before-quit", () => {
  stopFlaskBackend();
});
