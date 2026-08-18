// [Intent] Embedded Glassmorphism Web UI assets for Obsidian Studio Wi-Fi File Transfer
import Foundation

public struct WebAssets {
    public static let indexHTML: String = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Obsidian Studio &bull; Wi-Fi Media Transfer</title>
        <style>
            :root {
                --bg: #0B0C0E;
                --surface: #14161A;
                --elevated: #1E2127;
                --border: #282C35;
                --amber: #E5A93C;
                --text-primary: #FFFFFF;
                --text-secondary: #9AA0AC;
                --text-muted: #636B78;
                --success: #30D158;
            }
            * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
            body { background-color: var(--bg); color: var(--text-primary); min-height: 100vh; display: flex; flex-direction: column; align-items: center; padding: 40px 20px; }
            .container { width: 100%; max-width: 800px; }
            header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 30px; border-bottom: 1px solid var(--border); padding-bottom: 20px; }
            .brand { display: flex; align-items: center; gap: 12px; }
            .logo { width: 36px; height: 36px; background: var(--amber); border-radius: 8px; display: flex; align-items: center; justify-content: center; font-weight: bold; color: var(--bg); }
            h1 { font-size: 22px; font-weight: 700; letter-spacing: -0.5px; }
            .badge { font-size: 12px; background: var(--elevated); border: 1px solid var(--border); padding: 4px 10px; border-radius: 20px; color: var(--amber); }
            
            .drop-zone {
                background: var(--surface);
                border: 2px dashed var(--border);
                border-radius: 16px;
                padding: 50px 20px;
                text-align: center;
                cursor: pointer;
                transition: all 0.25s ease;
                margin-bottom: 30px;
            }
            .drop-zone:hover, .drop-zone.drag-over {
                border-color: var(--amber);
                background: var(--elevated);
                box-shadow: 0 0 20px rgba(229, 169, 60, 0.15);
            }
            .drop-icon { font-size: 40px; margin-bottom: 15px; color: var(--amber); }
            .drop-title { font-size: 18px; font-weight: 600; margin-bottom: 6px; }
            .drop-desc { font-size: 13px; color: var(--text-secondary); }
            
            .file-list-card {
                background: var(--surface);
                border: 1px solid var(--border);
                border-radius: 16px;
                padding: 24px;
            }
            .card-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 16px; font-weight: 600; font-size: 16px; }
            .file-table { width: 100%; border-collapse: collapse; text-align: left; font-size: 14px; }
            .file-table th { padding: 12px 8px; color: var(--text-muted); font-size: 12px; text-transform: uppercase; border-bottom: 1px solid var(--border); }
            .file-table td { padding: 14px 8px; border-bottom: 1px solid rgba(40, 44, 53, 0.5); }
            .file-name { font-weight: 500; }
            .file-size { color: var(--text-secondary); font-family: monospace; }
            .progress-bar-wrap { width: 100%; height: 6px; background: var(--elevated); border-radius: 3px; overflow: hidden; margin-top: 8px; display: none; }
            .progress-bar { width: 0%; height: 100%; background: var(--amber); transition: width 0.1s linear; }
        </style>
    </head>
    <body>
        <div class="container">
            <header>
                <div class="brand">
                    <div class="logo">&bull;</div>
                    <div>
                        <h1>Obsidian Studio</h1>
                        <p style="font-size: 13px; color: var(--text-secondary)">Wi-Fi File Transfer</p>
                    </div>
                </div>
                <div class="badge">Connected to iOS Device</div>
            </header>

            <div class="drop-zone" id="dropZone">
                <div class="drop-icon">&#8682;</div>
                <div class="drop-title">Drag & Drop Audio / Video Files Here</div>
                <div class="drop-desc">Supports MP4, MKV, FLAC, MP3, MOV, AAC, Subtitles (.srt, .ass)</div>
                <input type="file" id="fileInput" multiple style="display: none">
                <div class="progress-bar-wrap" id="progressWrap">
                    <div class="progress-bar" id="progressBar"></div>
                </div>
            </div>

            <div class="file-list-card">
                <div class="card-header">
                    <span>On-Device Media Files</span>
                    <button id="refreshBtn" style="background: var(--elevated); border: 1px solid var(--border); color: var(--text-primary); padding: 6px 12px; border-radius: 8px; cursor: pointer; font-size: 12px;">Refresh</button>
                </div>
                <table class="file-table">
                    <thead>
                        <tr>
                            <th>File Name</th>
                            <th>Size</th>
                            <th>Status</th>
                        </tr>
                    </thead>
                    <tbody id="fileTableBody">
                        <tr><td colspan="3" style="text-align: center; color: var(--text-muted); padding: 24px;">Loading files...</td></tr>
                    </tbody>
                </table>
            </div>
        </div>

        <script>
            const dropZone = document.getElementById('dropZone');
            const fileInput = document.getElementById('fileInput');
            const progressWrap = document.getElementById('progressWrap');
            const progressBar = document.getElementById('progressBar');
            const fileTableBody = document.getElementById('fileTableBody');
            const refreshBtn = document.getElementById('refreshBtn');

            dropZone.addEventListener('click', () => fileInput.click());
            dropZone.addEventListener('dragover', (e) => { e.preventDefault(); dropZone.classList.add('drag-over'); });
            dropZone.addEventListener('dragleave', () => dropZone.classList.remove('drag-over'));
            dropZone.addEventListener('drop', (e) => {
                e.preventDefault();
                dropZone.classList.remove('drag-over');
                if (e.dataTransfer.files.length > 0) uploadFiles(e.dataTransfer.files);
            });
            fileInput.addEventListener('change', () => { if (fileInput.files.length > 0) uploadFiles(fileInput.files); });
            refreshBtn.addEventListener('click', loadFiles);

            async function loadFiles() {
                try {
                    const res = await fetch('/api/files');
                    const files = await res.json();
                    if (!files || files.length === 0) {
                        fileTableBody.innerHTML = '<tr><td colspan="3" style="text-align: center; color: var(--text-muted); padding: 24px;">No files on device yet. Upload above!</td></tr>';
                        return;
                    }
                    fileTableBody.innerHTML = files.map(f => `
                        <tr>
                            <td class="file-name">${f.name}</td>
                            <td class="file-size">${formatBytes(f.size)}</td>
                            <td style="color: var(--success); font-size: 12px;">Ready</td>
                        </tr>
                    `).join('');
                } catch (e) {
                    fileTableBody.innerHTML = '<tr><td colspan="3" style="text-align: center; color: #FF453A; padding: 24px;">Failed to load files</td></tr>';
                }
            }

            async function uploadFiles(files) {
                progressWrap.style.display = 'block';
                for (let i = 0; i < files.length; i++) {
                    const file = files[i];
                    const formData = new FormData();
                    formData.append('file', file, file.name);

                    progressBar.style.width = '20%';
                    await fetch('/api/upload', { method: 'POST', body: formData });
                    progressBar.style.width = Math.round(((i + 1) / files.length) * 100) + '%';
                }
                setTimeout(() => {
                    progressWrap.style.display = 'none';
                    progressBar.style.width = '0%';
                    loadFiles();
                }, 500);
            }

            function formatBytes(bytes) {
                if (!bytes || bytes === 0) return '0 B';
                const k = 1024, sizes = ['B', 'KB', 'MB', 'GB'];
                const i = Math.floor(Math.log(bytes) / Math.log(k));
                return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
            }

            loadFiles();
        </script>
    </body>
    </html>
    """
}
