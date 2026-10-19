import Engine
import Foundation

// swiftlint:disable file_length
extension WebServerManager {

    // swiftlint:disable line_length
    static let mainPageHTML: String = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Albums</title>
        <style>
            :root {
                --bg: #f2f2f7;
                --card-bg: #ffffff;
                --text: #1c1c1e;
                --text-secondary: #8e8e93;
                --accent: #515BFE;
                --border: #d1d1d6;
                --hover: #e5e5ea;
                --header-bg: #ffffff;
                --shadow: rgba(0,0,0,0.08);
                --modal-bg: rgba(0,0,0,0.6);
            }
            @media (prefers-color-scheme: dark) {
                :root {
                    --bg: #000000;
                    --card-bg: #1c1c1e;
                    --text: #f5f5f7;
                    --text-secondary: #98989d;
                    --accent: #5E73FF;
                    --border: #38383a;
                    --hover: #2c2c2e;
                    --header-bg: #000000;
                    --shadow: rgba(0,0,0,0.3);
                    --modal-bg: rgba(0,0,0,0.8);
                }
            }
            * { margin: 0; padding: 0; box-sizing: border-box; user-select: none; -webkit-user-select: none; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
                background: var(--bg);
                color: var(--text);
                min-height: 100vh;
            }
            .header {
                position: sticky;
                top: 0;
                z-index: 100;
                background: color-mix(in srgb, var(--header-bg) 70%, transparent);
                border-bottom: 1px solid var(--border);
                padding: 16px 24px;
                display: flex;
                align-items: center;
                justify-content: space-between;
                backdrop-filter: saturate(180%) blur(20px);
                -webkit-backdrop-filter: saturate(180%) blur(20px);
            }
            .header h1 {
                font-size: 24px;
                font-weight: 700;
            }
            .header-actions { display: flex; gap: 8px; }
            .btn {
                display: inline-flex;
                align-items: center;
                gap: 6px;
                padding: 8px 16px;
                border: none;
                border-radius: 9999px;
                font-size: 14px;
                font-weight: 600;
                cursor: default;
            }
            .btn:hover { opacity: 0.8; }
            .btn-primary {
                background: var(--accent);
                color: white;
            }
            .breadcrumb {
                padding: 12px 24px;
                display: flex;
                align-items: center;
                gap: 4px;
                flex-wrap: wrap;
                font-size: 14px;
                color: var(--text-secondary);
            }
            .breadcrumb a {
                color: var(--accent);
                text-decoration: none;
                cursor: default;
            }
            .breadcrumb a:hover { text-decoration: underline; }
            .breadcrumb .separator { margin: 0 4px; }
            .content { padding: 0 24px 24px; }
            .section-title {
                font-size: 18px;
                font-weight: 600;
                margin: 20px 0 12px;
            }
            .album-grid {
                display: grid;
                grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
                gap: 12px;
            }
            .album-card {
                background: var(--card-bg);
                border-radius: 12px;
                overflow: hidden;
                cursor: default;
                transition: filter 0.15s;
                box-shadow: 0 1px 3px var(--shadow);
            }
            .album-card:hover {
                filter: brightness(0.85);
            }
            .album-cover {
                width: 100%;
                aspect-ratio: 1;
                background: var(--hover);
                display: flex;
                align-items: center;
                justify-content: center;
                overflow: hidden;
            }
            .album-cover img {
                width: 100%;
                height: 100%;
                object-fit: cover;
            }
            .album-info {
                padding: 10px 12px;
            }
            .album-name {
                font-size: 14px;
                font-weight: 600;
                white-space: nowrap;
                overflow: hidden;
                text-overflow: ellipsis;
            }
            .album-meta {
                font-size: 12px;
                color: var(--text-secondary);
                margin-top: 2px;
            }
            .pic-grid {
                display: grid;
                grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
                gap: 4px;
            }
            .pic-sentinel {
                width: 100%;
                height: 1px;
            }
            .pic-thumb {
                width: 100%;
                aspect-ratio: 1;
                object-fit: cover;
                border-radius: 4px;
                cursor: default;
                transition: filter 0.15s;
                background: var(--hover);
            }
            .pic-thumb:hover {
                filter: brightness(0.85);
            }
            .pic-cell {
                position: relative;
                aspect-ratio: 1;
                border-radius: 4px;
                overflow: hidden;
                cursor: default;
                transition: filter 0.15s;
                background: var(--hover);
            }
            .pic-cell:hover {
                filter: brightness(0.85);
            }
            .pic-cell img {
                width: 100%;
                height: 100%;
                object-fit: cover;
            }
            .video-badge {
                position: absolute;
                bottom: 6px;
                left: 6px;
                background: rgba(0,0,0,0.6);
                color: white;
                font-size: 11px;
                font-weight: 600;
                padding: 2px 6px;
                border-radius: 4px;
                backdrop-filter: blur(4px);
                -webkit-backdrop-filter: blur(4px);
            }
            .modal-overlay {
                position: fixed;
                inset: 0;
                background: var(--modal-bg);
                z-index: 200;
                display: flex;
                align-items: center;
                justify-content: center;
                opacity: 0;
                pointer-events: none;
                transition: opacity 0.2s;
            }
            .modal-overlay.active {
                opacity: 1;
                pointer-events: auto;
            }
            .viewer-content {
                position: relative;
                max-width: 90vw;
                max-height: 90vh;
                display: flex;
                flex-direction: column;
                align-items: center;
            }
            .viewer-content img, .viewer-content video {
                max-width: 90vw;
                max-height: 80vh;
                object-fit: contain;
                border-radius: 8px;
            }
            .viewer-controls {
                display: flex;
                gap: 12px;
                margin-top: 16px;
            }
            .viewer-controls .btn {
                background: rgba(255,255,255,0.2);
                color: white;
                backdrop-filter: blur(10px);
            }
            .viewer-name {
                color: white;
                font-size: 14px;
                margin-top: 8px;
                opacity: 0.8;
            }
            .upload-modal {
                background: var(--card-bg);
                border-radius: 16px;
                padding: 24px;
                max-width: 480px;
                width: 90vw;
            }
            .upload-modal h2 {
                font-size: 20px;
                margin-bottom: 16px;
            }
            .upload-drop-zone {
                border: 2px dashed var(--border);
                border-radius: 12px;
                padding: 40px 20px;
                text-align: center;
                line-height: 1.5;
                color: var(--text-secondary);
                margin-bottom: 16px;
                transition: border-color 0.15s, background 0.15s;
            }
            .upload-drop-zone.dragover {
                border-color: var(--accent);
                background: rgba(0, 122, 255, 0.05);
            }
            .upload-drop-zone input[type="file"] {
                display: none;
            }
            .upload-drop-zone label {
                color: var(--accent);
                cursor: default;
                font-weight: 600;
            }
            .upload-actions {
                display: flex;
                gap: 8px;
                justify-content: flex-end;
            }
            .btn-secondary {
                background: var(--hover);
                color: var(--text);
            }
            .upload-progress {
                margin: 12px 0;
                font-size: 14px;
                color: var(--text-secondary);
            }
            .progress-bar {
                width: 100%;
                height: 4px;
                background: var(--hover);
                border-radius: 2px;
                overflow: hidden;
                margin-top: 8px;
            }
            .progress-bar-fill {
                height: 100%;
                background: var(--accent);
                transition: width 0.3s;
                width: 0%;
            }
            .empty-state {
                text-align: center;
                padding: 60px 20px;
                color: var(--text-secondary);
            }
            .empty-state p { font-size: 16px; }
            .loading {
                text-align: center;
                padding: 60px;
                color: var(--text-secondary);
            }
            @media (max-width: 600px) {
                .header { padding: 12px 16px; }
                .header h1 { font-size: 20px; }
                .breadcrumb { padding: 8px 16px; }
                .content { padding: 0 16px 16px; }
                .album-grid { grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap: 12px; }
                .pic-grid { grid-template-columns: repeat(auto-fill, minmax(100px, 1fr)); gap: 6px; }
            }
        </style>
    </head>
    <body>
        <div class="header">
            <h1 id="pageTitle">Albums</h1>
            <div class="header-actions">
                <button class="btn btn-primary" id="uploadBtn" onclick="openUpload()">
                    Upload
                </button>
            </div>
        </div>
        <div class="breadcrumb" id="breadcrumb"></div>
        <div class="content" id="content">
            <div class="loading">Loading...</div>
        </div>

        <!-- Image/Video Viewer Modal -->
        <div class="modal-overlay" id="viewerModal" onclick="closeViewer(event)">
            <div class="viewer-content">
                <img id="viewerImage" src="" alt="">
                <video id="viewerVideo" controls playsinline style="display:none"></video>
                <div class="viewer-name" id="viewerName"></div>
                <div class="viewer-controls">
                    <a class="btn" id="downloadLink" download style="text-decoration:none">Download</a>
                    <button class="btn" onclick="closeViewer()">Close</button>
                </div>
            </div>
        </div>

        <!-- Upload Modal -->
        <div class="modal-overlay" id="uploadModal">
            <div class="upload-modal">
                <h2>Upload Pics</h2>
                <div class="upload-drop-zone" id="dropZone">
                    <p>Drag and drop images here, or</p>
                    <p><label for="fileInput">browse files</label></p>
                    <input type="file" id="fileInput" multiple accept="image/*">
                </div>
                <div id="fileList"></div>
                <div class="upload-progress" id="uploadProgress" style="display:none">
                    <span id="uploadStatusText">Uploading...</span>
                    <div class="progress-bar">
                        <div class="progress-bar-fill" id="progressBarFill"></div>
                    </div>
                </div>
                <div class="upload-actions" id="uploadActions">
                    <button class="btn btn-secondary" onclick="closeUpload()">Cancel</button>
                    <button class="btn btn-primary" id="uploadSubmitBtn" onclick="submitUpload()">Upload</button>
                </div>
            </div>
        </div>

        <script>
            // State
            let currentPath = [];
            let currentAlbumId = null;
            let selectedFiles = [];

            // Lazy pic loading state
            const PIC_PAGE_SIZE = 60;
            let totalPicCount = 0;
            let loadedPicCount = 0;
            let isLoadingPics = false;
            let picGridEl = null;
            let picSentinel = null;
            let picObserver = null;
            let picLoadToken = 0;

            // Navigation
            function currentPathUrl() {
                if (currentPath.length === 0) return '/';
                return '/' + currentPath.map(p => encodeURIComponent(p.id)).join('/');
            }

            function syncUrl(push) {
                const url = currentPathUrl();
                if (push) {
                    if (url !== location.pathname) history.pushState({}, '', url);
                } else {
                    history.replaceState({}, '', url);
                }
            }

            function showContentError(message) {
                document.getElementById('content').innerHTML =
                    '<div class="empty-state"><p>' + message + '</p></div>';
            }

            async function loadRoot(push = true) {
                try {
                    const resp = await fetch('/api/albums');
                    const data = await resp.json();
                    currentPath = [];
                    currentAlbumId = null;
                    renderContent(data);
                    renderBreadcrumb();
                    syncUrl(push);
                } catch (err) {
                    showContentError('Failed to load. Please try again.');
                }
            }

            async function loadAlbum(id, push = true) {
                try {
                    const resp = await fetch('/api/albums/' + encodeURIComponent(id));
                    if (!resp.ok) { await loadRoot(false); return; }
                    const data = await resp.json();
                    const path = (data.path && data.path.length)
                        ? data.path
                        : [{ id: data.id, name: data.name }];
                    currentPath = path.map(p => ({ id: p.id, name: p.name }));
                    currentAlbumId = data.id;
                    renderContent(data);
                    renderBreadcrumb();
                    syncUrl(push);
                } catch (err) {
                    showContentError('Failed to load album.');
                }
            }

            function navigateTo(index) {
                if (index < 0) {
                    loadRoot();
                } else {
                    loadAlbum(currentPath[index].id);
                }
            }

            function restoreFromUrl() {
                const ids = location.pathname.split('/').filter(Boolean);
                if (ids.length === 0) {
                    loadRoot(false);
                } else {
                    loadAlbum(decodeURIComponent(ids[ids.length - 1]), false);
                }
            }

            // Rendering
            function renderBreadcrumb() {
                const el = document.getElementById('breadcrumb');
                el.innerHTML = '';
                const rootLink = document.createElement('a');
                rootLink.textContent = 'Collection';
                rootLink.addEventListener('click', () => navigateTo(-1));
                el.appendChild(rootLink);
                currentPath.forEach((item, idx) => {
                    const sep = document.createElement('span');
                    sep.className = 'separator';
                    sep.textContent = '/';
                    el.appendChild(sep);
                    if (idx === currentPath.length - 1) {
                        const span = document.createElement('span');
                        span.textContent = item.name;
                        el.appendChild(span);
                    } else {
                        const link = document.createElement('a');
                        link.textContent = item.name;
                        const navIdx = idx;
                        link.addEventListener('click', () => navigateTo(navIdx));
                        el.appendChild(link);
                    }
                });
            }

            function renderContent(data) {
                const el = document.getElementById('content');
                teardownPicLoading();
                el.innerHTML = '';

                const hasAlbums = data.albums && data.albums.length > 0;
                totalPicCount = (typeof data.picCount === 'number')
                    ? data.picCount
                    : ((data.pics && data.pics.length) || 0);
                const hasPics = totalPicCount > 0;

                if (!hasAlbums && !hasPics) {
                    el.innerHTML = '<div class="empty-state"><p>No albums or pics here yet.</p></div>';
                    return;
                }

                if (hasAlbums) {
                    const title = document.createElement('div');
                    title.className = 'section-title';
                    title.textContent = 'Albums';
                    el.appendChild(title);

                    const grid = document.createElement('div');
                    grid.className = 'album-grid';
                    data.albums.forEach(album => {
                        const card = document.createElement('div');
                        card.className = 'album-card';
                        card.addEventListener('click', () => loadAlbum(album.id));

                        const cover = document.createElement('div');
                        cover.className = 'album-cover';
                        if (album.hasCover) {
                            const img = document.createElement('img');
                            img.src = '/api/albums/' + encodeURIComponent(album.id) + '/cover';
                            img.loading = 'lazy';
                            cover.appendChild(img);
                        }
                        card.appendChild(cover);

                        const info = document.createElement('div');
                        info.className = 'album-info';
                        const nameEl = document.createElement('div');
                        nameEl.className = 'album-name';
                        nameEl.textContent = album.name;
                        info.appendChild(nameEl);
                        const metaEl = document.createElement('div');
                        metaEl.className = 'album-meta';
                        let metaParts = [];
                        if (album.albumCount > 0) metaParts.push(album.albumCount + ' album' + (album.albumCount !== 1 ? 's' : ''));
                        if (album.picCount > 0) metaParts.push(album.picCount + ' pic' + (album.picCount !== 1 ? 's' : ''));
                        metaEl.textContent = metaParts.join(', ') || 'Empty';
                        info.appendChild(metaEl);
                        card.appendChild(info);

                        grid.appendChild(card);
                    });
                    el.appendChild(grid);
                }

                if (hasPics) {
                    const title = document.createElement('div');
                    title.className = 'section-title';
                    title.textContent = 'Pics';
                    el.appendChild(title);

                    picGridEl = document.createElement('div');
                    picGridEl.className = 'pic-grid';
                    el.appendChild(picGridEl);

                    loadedPicCount = 0;
                    appendPics(data.pics || []);

                    if (loadedPicCount < totalPicCount) {
                        picSentinel = document.createElement('div');
                        picSentinel.className = 'pic-sentinel';
                        el.appendChild(picSentinel);
                        picObserver = new IntersectionObserver((entries) => {
                            if (entries.some(e => e.isIntersecting)) {
                                loadMorePics();
                            }
                        }, { rootMargin: '800px 0px' });
                        picObserver.observe(picSentinel);
                    }
                }
            }

            function appendPics(pics) {
                if (!picGridEl) return;
                pics.forEach(pic => {
                    if (pic.isVideo) {
                        const cell = document.createElement('div');
                        cell.className = 'pic-cell';
                        const img = document.createElement('img');
                        img.src = '/api/pics/' + encodeURIComponent(pic.id) + '/thumbnail';
                        img.alt = pic.name;
                        img.loading = 'lazy';
                        cell.appendChild(img);
                        const badge = document.createElement('div');
                        badge.className = 'video-badge';
                        if (pic.duration) {
                            const m = Math.floor(pic.duration / 60);
                            const s = Math.floor(pic.duration % 60);
                            badge.textContent = m + ':' + (s < 10 ? '0' : '') + s;
                        } else {
                            badge.textContent = 'Video';
                        }
                        cell.appendChild(badge);
                        cell.addEventListener('click', () => openViewer(pic.id, pic.name, true));
                        picGridEl.appendChild(cell);
                    } else {
                        const img = document.createElement('img');
                        img.className = 'pic-thumb';
                        img.src = '/api/pics/' + encodeURIComponent(pic.id) + '/thumbnail';
                        img.alt = pic.name;
                        img.loading = 'lazy';
                        img.addEventListener('click', () => openViewer(pic.id, pic.name, false));
                        picGridEl.appendChild(img);
                    }
                });
                loadedPicCount += pics.length;
            }

            async function loadMorePics() {
                if (isLoadingPics || loadedPicCount >= totalPicCount) return;
                isLoadingPics = true;
                const token = picLoadToken;
                const base = currentAlbumId
                    ? '/api/albums/' + encodeURIComponent(currentAlbumId) + '/pics'
                    : '/api/pics';
                const url = base + '?offset=' + loadedPicCount + '&limit=' + PIC_PAGE_SIZE;
                try {
                    const resp = await fetch(url);
                    const data = await resp.json();
                    if (token !== picLoadToken) return;
                    const pics = data.pics || [];
                    appendPics(pics);
                    if (pics.length === 0 || loadedPicCount >= totalPicCount) {
                        teardownPicLoading();
                    } else if (picObserver && picSentinel) {
                        // Re-arm so a sentinel still in view keeps filling the viewport.
                        picObserver.unobserve(picSentinel);
                        picObserver.observe(picSentinel);
                    }
                } catch (err) {
                    // Leave the observer connected so the next scroll retries.
                } finally {
                    if (token === picLoadToken) isLoadingPics = false;
                }
            }

            function teardownPicLoading() {
                picLoadToken++;
                isLoadingPics = false;
                if (picObserver) {
                    picObserver.disconnect();
                    picObserver = null;
                }
                if (picSentinel && picSentinel.parentElement) {
                    picSentinel.remove();
                }
                picSentinel = null;
            }

            // Image/Video Viewer
            function openViewer(picId, picName, isVideo) {
                const modal = document.getElementById('viewerModal');
                const img = document.getElementById('viewerImage');
                const video = document.getElementById('viewerVideo');
                const name = document.getElementById('viewerName');
                const dl = document.getElementById('downloadLink');

                if (isVideo) {
                    const videoUrl = '/api/pics/' + encodeURIComponent(picId) + '/video';
                    img.style.display = 'none';
                    video.style.display = 'block';
                    video.src = videoUrl;
                    dl.href = videoUrl;
                    dl.download = picName;
                } else {
                    const fullUrl = '/api/pics/' + encodeURIComponent(picId) + '/image';
                    video.style.display = 'none';
                    img.style.display = 'block';
                    img.src = fullUrl;
                    dl.href = fullUrl;
                    dl.download = picName;
                }

                name.textContent = picName;
                modal.classList.add('active');
                document.body.style.overflow = 'hidden';
            }

            function closeViewer(event) {
                if (event && event.target !== event.currentTarget) return;
                const modal = document.getElementById('viewerModal');
                const video = document.getElementById('viewerVideo');
                modal.classList.remove('active');
                document.getElementById('viewerImage').src = '';
                video.pause();
                video.removeAttribute('src');
                video.load();
                document.body.style.overflow = '';
            }

            // Upload
            function openUpload() {
                document.getElementById('uploadModal').classList.add('active');
                document.getElementById('fileInput').value = '';
                document.getElementById('fileList').innerHTML = '';
                document.getElementById('uploadProgress').style.display = 'none';
                document.getElementById('uploadActions').style.display = '';
                selectedFiles = [];
                document.body.style.overflow = 'hidden';
            }

            function closeUpload() {
                document.getElementById('uploadModal').classList.remove('active');
                document.body.style.overflow = '';
                selectedFiles = [];
            }

            // Drop zone
            const dropZone = document.getElementById('dropZone');
            dropZone.addEventListener('dragover', (e) => {
                e.preventDefault();
                dropZone.classList.add('dragover');
            });
            dropZone.addEventListener('dragleave', () => {
                dropZone.classList.remove('dragover');
            });
            dropZone.addEventListener('drop', (e) => {
                e.preventDefault();
                dropZone.classList.remove('dragover');
                if (e.dataTransfer.files.length > 0) {
                    selectedFiles = Array.from(e.dataTransfer.files).slice(0, 50);
                    updateFileList();
                }
            });
            document.getElementById('fileInput').addEventListener('change', (e) => {
                selectedFiles = Array.from(e.target.files).slice(0, 50);
                updateFileList();
            });

            function updateFileList() {
                const el = document.getElementById('fileList');
                if (selectedFiles.length === 0) {
                    el.innerHTML = '';
                    return;
                }
                let msg = selectedFiles.length + ' file' + (selectedFiles.length !== 1 ? 's' : '') + ' selected';
                if (selectedFiles.length === 50) {
                    msg += ' (maximum 50)';
                }
                el.innerHTML = '<p style="font-size:14px;color:var(--text-secondary);margin:8px 0">' + msg + '</p>';
            }

            async function submitUpload() {
                if (selectedFiles.length === 0) return;

                const actions = document.getElementById('uploadActions');
                const progress = document.getElementById('uploadProgress');
                const statusText = document.getElementById('uploadStatusText');
                const progressFill = document.getElementById('progressBarFill');

                actions.style.display = 'none';
                progress.style.display = 'block';
                statusText.textContent = 'Uploading...';
                progressFill.style.width = '0%';

                const formData = new FormData();
                for (const file of selectedFiles) {
                    formData.append('file', file);
                }

                const url = currentAlbumId
                    ? '/api/albums/' + encodeURIComponent(currentAlbumId) + '/upload'
                    : '/api/upload';

                try {
                    const resp = await fetch(url, { method: 'POST', body: formData });
                    const result = await resp.json();
                    progressFill.style.width = '100%';
                    statusText.textContent = result.uploaded + ' image' + (result.uploaded !== 1 ? 's' : '') + ' uploaded!';
                    setTimeout(() => {
                        closeUpload();
                        if (currentAlbumId) {
                            loadAlbum(currentAlbumId, false);
                        } else {
                            loadRoot(false);
                        }
                    }, 1000);
                } catch (err) {
                    statusText.textContent = 'Upload failed. Please try again.';
                    actions.style.display = '';
                }
            }

            // Keyboard
            document.addEventListener('keydown', (e) => {
                if (e.key === 'Escape') {
                    closeViewer();
                    closeUpload();
                }
            });

            // Routing
            window.addEventListener('popstate', () => restoreFromUrl());

            // Init
            restoreFromUrl();
        </script>
    </body>
    </html>
    """
    // swiftlint:enable line_length
}
// swiftlint:enable file_length
