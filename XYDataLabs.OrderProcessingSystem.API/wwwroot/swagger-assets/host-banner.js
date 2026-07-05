(function () {
    const bannerId = 'swagger-host-banner';

    const ensureBanner = () => {
        const swaggerTopbar = document.querySelector('.swagger-ui .topbar');
        if (!swaggerTopbar) {
            return false;
        }

        let banner = document.getElementById(bannerId);
        if (!banner) {
            banner = document.createElement('div');
            banner.id = bannerId;
            banner.style.background = '#0f172a';
            banner.style.color = '#e2e8f0';
            banner.style.padding = '8px 16px';
            banner.style.fontSize = '13px';
            banner.style.borderBottom = '1px solid rgba(148,163,184,0.35)';
            banner.style.fontFamily = 'monospace';
            banner.style.whiteSpace = 'pre-wrap';
            swaggerTopbar.parentElement.insertBefore(banner, swaggerTopbar.nextSibling);
        }

        banner.textContent = `Accepted host: ${window.location.host}`;
        return true;
    };

    const tryRender = () => {
        if (ensureBanner()) {
            return;
        }

        window.setTimeout(tryRender, 250);
    };

    window.addEventListener('load', () => {
        tryRender();
    });
})();
