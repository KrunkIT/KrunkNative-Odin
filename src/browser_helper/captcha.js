// Installed before the official page's scripts, only in its top-level context.
(() => {
    if (window !== window.top || location.origin !== 'https://krunker.io') return;
    if (window.__krodinCaptchaHandoff) return;
    const state = window.__krodinCaptchaHandoff = {state: 'WAIT_CAPTCHA', token: '', assignment: '', sockets: []};
    const expectedGame = window.__krodinCaptchaGame;
    let pendingAssignment = null;
    const closeSockets = () => {
        for (const socket of state.sockets.splice(0)) {
            try { socket.close(1000, 'native client owns the game connection'); } catch {}
        }
    };
    const requestUrl = input => {
        try {
            const url = new URL(typeof input === 'string' || input instanceof URL ? input : input.url, location.href);
            return url.origin === 'https://matchmaker.krunker.io' && url.pathname === '/seek-game' ? url : null;
        } catch { return null; }
    };
    const inspect = input => {
        const url = requestUrl(input);
        if (!url) return false;
        const token = url.searchParams.get('captchaToken');
        if (!token) return false;
        if (url.searchParams.get('game') !== expectedGame) {
            state.state = 'CAPTCHA_WRONG_INVITE';
            return true;
        }
        if (!state.token && !state.assignment) {
            if (token.length > 16384 || !/^[\x21-\x7e]+$/.test(token)) state.state = 'CAPTCHA_BAD_TOKEN';
            else { state.token = token; state.state = 'CAPTCHA_READY'; closeSockets(); }
        }
        return true;
    };
    const observeAssignment = (value, sourceUrl) => {
        try {
            if (sourceUrl.searchParams.get('game') !== expectedGame || state.token || state.assignment) return;
            if (typeof value === 'string') value = JSON.parse(value);
            const {host, gameId} = value || {};
            const clientId = value?.clientId || value?.clientKey;
            if (typeof host !== 'string' || typeof gameId !== 'string' || typeof clientId !== 'string') return;
            if (!host || host.length > 512 || !clientId || clientId.length > 4096 || !gameId || gameId.length > 128) return;
            pendingAssignment = {host, gameId, clientId};
            state.state = 'WAIT_SOCKET_INTENT';
        } catch {}
    };
    const originalFetch = window.fetch;
    window.fetch = function(input, ...args) {
        if (inspect(input)) return new Promise(() => {});
        const url = requestUrl(input);
        const result = originalFetch.call(this, input, ...args);
        if (!url) return result;
        return Promise.resolve(result).then(async response => {
            // Let the page process the assignment, refresh its JWT and build
            // its complete socket URL. The constructor stops the actual socket.
            try {
                if (response.ok !== false) observeAssignment(await response.clone().json(), url);
            } catch {}
            return response;
        });
    };
    const urls = new WeakMap();
    const trackedXHR = new Set();
    const originalOpen = XMLHttpRequest.prototype.open;
    const originalSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function(method, url, ...args) {
        urls.set(this, url);
        return originalOpen.call(this, method, url, ...args);
    };
    XMLHttpRequest.prototype.send = function(...args) {
        const url = requestUrl(urls.get(this));
        if (inspect(url)) return;
        // Inspect DONE responses in the socket constructor, regardless of
        // whether a page load/readystatechange handler runs before ours.
        if (url && !url.searchParams.get('captchaToken')) trackedXHR.add(this);
        return originalSend.apply(this, args);
    };
    const readXHR = () => {
        for (const xhr of trackedXHR) {
            if (xhr.readyState !== 4) continue;
            trackedXHR.delete(xhr);
            try {
                if (xhr.status < 200 || xhr.status >= 300) continue;
                observeAssignment(xhr.responseType === 'json' ? xhr.response : xhr.responseText, requestUrl(urls.get(xhr)));
            } catch {}
        }
    };
    window.WebSocket = new Proxy(window.WebSocket, {
        construct(target, args) {
            const url = new URL(args[0], location.href);
            if (!url.hostname.endsWith('.krunker.io') || url.pathname !== '/ws') return Reflect.construct(target, args);
            if (state.token || state.assignment) throw new DOMException('The native client owns the game connection.', 'InvalidStateError');
            readXHR();
            if (pendingAssignment) {
                const assignment = pendingAssignment;
                if (url.protocol !== 'wss:' || url.hostname !== assignment.host ||
                    url.searchParams.get('gameId') !== assignment.gameId || url.searchParams.get('clientKey') !== assignment.clientId) {
                    state.state = 'CAPTCHA_SOCKET_MISMATCH';
                } else {
                    let username = '';
                    try { username = localStorage.getItem('krunker_username') || ''; } catch {}
                    if (!username.trim()) state.state = 'CAPTCHA_LOGIN_REQUIRED';
                    else if (!url.searchParams.get('at')) state.state = 'CAPTCHA_BAD_TOKEN';
                    else {
                        // Only private IPC receives credentials. Preserve the
                        // URL the page chose, including its freshly selected JWT.
                        state.assignment = JSON.stringify({...assignment, websocketUrl: url.href, usernamePresent: true});
                        state.state = 'CAPTCHA_ASSIGNMENT';
                    }
                }
                closeSockets();
                throw new DOMException('The native client owns the game connection.', 'InvalidStateError');
            }
            // A provisional socket can be needed to trigger the site's challenge.
            const socket = Reflect.construct(target, args);
            state.sockets.push(socket);
            return socket;
        }
    });
})();
