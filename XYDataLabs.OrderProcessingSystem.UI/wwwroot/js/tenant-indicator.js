(function () {
    const indicator = document.getElementById('tenant-indicator');
    const apiBaseUrl = document.body?.dataset?.apiBaseUrl;

    if (!indicator || !apiBaseUrl) {
        return;
    }

    const runtimeConfigurationUrl = `${apiBaseUrl.replace(/\/$/, '')}/api/v1/info/runtime-configuration`;

    fetch(runtimeConfigurationUrl, {
        method: 'GET',
        headers: {
            'Accept': 'application/json'
        }
    })
        .then(async response => {
            const payload = await response.json().catch(() => null);

            if (!response.ok || !payload?.activeTenantCode) {
                throw new Error(payload?.detail || payload?.message || 'Tenant unavailable');
            }

            indicator.textContent = `Tenant: ${payload.activeTenantCode}`;
            indicator.classList.remove('bg-dark');
            indicator.classList.add('bg-primary');
        })
        .catch(() => {
            indicator.textContent = 'Tenant: unavailable';
            indicator.classList.remove('bg-dark');
            indicator.classList.add('bg-danger');
        });
})();