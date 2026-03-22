(function () {
    const tenantStorageKey = 'order-processing:selected-tenant';
    const runtimeConfigurationUrl = '/api/v1/info/runtime-configuration';
    const tenantHeaderName = 'X-Tenant-Code';
    let selectedTenantCode = null;
    let availableTenants = [];

    const getStoredTenantCode = () => {
        try {
            return window.localStorage.getItem(tenantStorageKey);
        } catch (error) {
            console.warn('Unable to read stored Swagger tenant selection.', error);
            return null;
        }
    };

    const persistTenantCode = tenantCode => {
        try {
            if (!tenantCode) {
                window.localStorage.removeItem(tenantStorageKey);
                return;
            }

            window.localStorage.setItem(tenantStorageKey, tenantCode);
        } catch (error) {
            console.warn('Unable to persist Swagger tenant selection.', error);
        }
    };

    const syncTenantHeaderInputs = () => {
        if (!selectedTenantCode) {
            return;
        }

        const tenantParameterNames = Array.from(document.querySelectorAll('.parameter__name, .parameters-col_name'))
            .filter(element => element.textContent?.trim() === tenantHeaderName);

        for (const parameterName of tenantParameterNames) {
            const parameterContainer = parameterName.closest('tr')
                || parameterName.closest('.parameter__in')
                || parameterName.closest('.parameters-container')
                || parameterName.parentElement;

            if (!parameterContainer) {
                continue;
            }

            const inputs = Array.from(parameterContainer.querySelectorAll('input, textarea'))
                .filter(input => input.id !== 'swagger-tenant-selector');

            for (const input of inputs) {
                if (input.value === selectedTenantCode) {
                    lockTenantHeaderInput(input);
                    continue;
                }

                input.value = selectedTenantCode;
                input.dispatchEvent(new Event('input', { bubbles: true }));
                input.dispatchEvent(new Event('change', { bubbles: true }));
                lockTenantHeaderInput(input);
            }
        }
    };

    const lockTenantHeaderInput = input => {
        input.readOnly = true;
        input.setAttribute('aria-readonly', 'true');
        input.setAttribute('title', 'Controlled by the Swagger tenant selector.');
        input.style.backgroundColor = '#f3f4f6';
        input.style.cursor = 'not-allowed';
    };

    const scheduleTenantHeaderSync = () => {
        window.setTimeout(syncTenantHeaderInputs, 0);
        window.setTimeout(syncTenantHeaderInputs, 150);
        window.setTimeout(syncTenantHeaderInputs, 500);
    };

    const resolveTenantCode = (payload, preferredTenantCode) => {
        const tenants = Array.isArray(payload?.availableTenants) ? payload.availableTenants : [];
        const preferredMatch = tenants.find(tenant =>
            typeof preferredTenantCode === 'string'
            && preferredTenantCode.length > 0
            && tenant.tenantCode.toLowerCase() === preferredTenantCode.toLowerCase());

        if (preferredMatch) {
            return preferredMatch.tenantCode;
        }

        if (payload?.activeTenantCode) {
            return payload.activeTenantCode;
        }

        return tenants[0]?.tenantCode || null;
    };

    const patchFetch = () => {
        if (window.__orderProcessingTenantFetchPatched) {
            return;
        }

        const originalFetch = window.fetch.bind(window);
        window.fetch = function (input, init) {
            const requestUrl = input instanceof Request ? input.url : input;
            const absoluteUrl = new URL(requestUrl, window.location.origin);
            const isSameOriginApiRequest = absoluteUrl.origin === window.location.origin
                && absoluteUrl.pathname.startsWith('/api/');
            const isRuntimeConfigurationRequest = absoluteUrl.pathname === runtimeConfigurationUrl;

            if (!isSameOriginApiRequest || isRuntimeConfigurationRequest || !selectedTenantCode) {
                return originalFetch(input, init);
            }

            if (input instanceof Request) {
                const headers = new Headers(init?.headers || input.headers || undefined);
                headers.set(tenantHeaderName, selectedTenantCode);
                return originalFetch(new Request(input, { headers }), init);
            }

            const requestInit = { ...(init || {}) };
            const headers = new Headers(requestInit.headers || undefined);
            headers.set(tenantHeaderName, selectedTenantCode);
            requestInit.headers = headers;

            return originalFetch(input, requestInit);
        };

        window.__orderProcessingTenantFetchPatched = true;
    };

    const upsertSelector = () => {
        const topbarWrapper = document.querySelector('.swagger-ui .topbar-wrapper');
        if (!topbarWrapper) {
            return false;
        }

        let container = document.getElementById('swagger-tenant-selector-container');
        if (!container) {
            container = document.createElement('div');
            container.id = 'swagger-tenant-selector-container';
            container.style.display = 'flex';
            container.style.alignItems = 'center';
            container.style.gap = '8px';
            container.style.marginLeft = '16px';
            container.style.color = 'white';

            const label = document.createElement('label');
            label.htmlFor = 'swagger-tenant-selector';
            label.textContent = 'Tenant';
            label.style.fontSize = '14px';
            label.style.fontWeight = '600';

            const select = document.createElement('select');
            select.id = 'swagger-tenant-selector';
            select.style.padding = '4px 8px';
            select.style.borderRadius = '4px';
            select.style.border = '1px solid rgba(255,255,255,0.35)';
            select.style.background = 'white';
            select.style.color = '#1f2937';

            select.addEventListener('change', event => {
                const newTenantCode = event.target.value || null;
                if (newTenantCode === selectedTenantCode) {
                    return;
                }

                selectedTenantCode = newTenantCode;
                persistTenantCode(selectedTenantCode);
                reloadSwaggerUi();
            });

            container.appendChild(label);
            container.appendChild(select);
            topbarWrapper.appendChild(container);
        }

        const select = document.getElementById('swagger-tenant-selector');
        if (!select) {
            return false;
        }

        select.innerHTML = '';
        for (const tenant of availableTenants) {
            const option = document.createElement('option');
            option.value = tenant.tenantCode;
            option.textContent = `${tenant.tenantName} (${tenant.tenantCode})`;
            select.appendChild(option);
        }

        if (selectedTenantCode) {
            select.value = selectedTenantCode;
        }

        scheduleTenantHeaderSync();

        return true;
    };

    const ensureSelector = () => {
        let attemptsRemaining = 20;

        const tryRender = () => {
            if (upsertSelector() || attemptsRemaining <= 0) {
                return;
            }

            attemptsRemaining -= 1;
            window.setTimeout(tryRender, 300);
        };

        tryRender();
    };

    const reloadSwaggerUi = () => {
        if (window.location.hash) {
            window.location.assign(window.location.pathname + window.location.search);
            return;
        }

        window.location.reload();
    };

    const initialize = async () => {
        patchFetch();

        const preferredTenantCode = getStoredTenantCode();
        const headers = {
            'Accept': 'application/json'
        };

        if (preferredTenantCode) {
            headers[tenantHeaderName] = preferredTenantCode;
        }

        const response = await window.fetch(runtimeConfigurationUrl, { headers });
        const payload = await response.json();

        if (!response.ok || !payload?.activeTenantCode) {
            throw new Error(payload?.detail || 'Unable to load runtime tenant configuration for Swagger.');
        }

        availableTenants = Array.isArray(payload.availableTenants) ? payload.availableTenants : [];
        selectedTenantCode = resolveTenantCode(payload, preferredTenantCode);
        persistTenantCode(selectedTenantCode);
        ensureSelector();
        scheduleTenantHeaderSync();

        const observer = new MutationObserver(() => {
            scheduleTenantHeaderSync();
        });

        observer.observe(document.body, {
            childList: true,
            subtree: true
        });
    };

    window.addEventListener('load', () => {
        initialize().catch(error => {
            console.error('Unable to initialize Swagger tenant selector.', error);
        });
    });
})();
