{
  "name": "sheet-ingestor",
  "version": "1.0.0",
  "description": "Electron + Python app to ingest, convert, map and preview Excel sheets",
  "main": "main.js",
  "scripts": {
    "dev": "concurrently \"vite\" \"wait-on tcp:5173 && cross-env ELECTRON_DEV=1 electron .\"",
    "build:vite": "vite build",
    "start": "npm run build:vite && electron .",
    "dist:win": "npm run build:vite && electron-builder --win"
  },
  "dependencies": {
    "axios": "1.10.0",
    "react": "18.3.1",
    "react-dom": "18.3.1"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "6.0.2",
    "concurrently": "8.2.2",
    "cross-env": "10.1.0",
    "electron": "42.4.0",
    "electron-builder": "^26.15.3",
    "vite": "8.0.16",
    "wait-on": "9.0.10"
  },
  "build": {
    "appId": "com.yourcompany.sheetingestor",
    "productName": "SheetIngestor",
    "win": {
      "target": "nsis",
      "icon": "build/icon.ico"
    },
    "files": [
      "main.js",
      "preload.js",
      "dist-renderer/**/*",
      "package.json"
    ],
    "extraResources": [
      {
        "from": "python_backend/dist/app.exe",
        "to": "python_backend/app.exe"
      }
    ]
  }
}
