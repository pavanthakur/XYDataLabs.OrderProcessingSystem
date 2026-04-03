window.OrderProcessingTenant = (() => {
    const bodyDataset = document.body?.dataset || {};
    const indicator = document.getElementById('tenant-indicator');
    const selector = document.getElementById('tenant-selector');
    const apiBaseUrl = bodyDataset.apiBaseUrl?.replace(/\/$/, '');
    const uiTenantOverrideEnabled = bodyDataset.uiTenantOverrideEnabled === 'true';
    const runtimeConfigurationUrl = apiBaseUrl
        ? `${apiBaseUrl}/api/v1/info/runtime-configuration`
        : null;

    let state = null;
    let readyPromise = null;

    const clearLegacyStoredTenantCode = () => {
        try {
            localStorage.removeItem('order-processing:selected-tenant');
        } catch (error) {
            console.warn('Unable to clear legacy stored tenant selection.', error);
        }
    };

    const getUrlTenantCode = () => {
        const urlParams = new URLSearchParams(window.location.search);
        return urlParams.get('tenantCode')?.trim() || null;
    };

    const stripTenantCodeFromUrl = () => {
        const url = new URL(window.location.href);
        if (!url.searchParams.has('tenantCode')) {
            return;
        }

        url.searchParams.delete('tenantCode');
        history.replaceState({}, '', `${url.pathname}${url.search}${url.hash}`);
    };

    const setIndicatorState = (text, badgeClass) => {
        if (!indicator) {
            return;
        }

        indicator.textContent = text;
        indicator.classList.remove('bg-dark', 'bg-primary', 'bg-danger', 'bg-secondary');
        indicator.classList.add(badgeClass);
    };

    const syncSelector = availableTenants => {
        if (!selector) {
            return;
        }

        selector.innerHTML = '';

        if (!Array.isArray(availableTenants) || availableTenants.length === 0) {
            const option = document.createElement('option');
            option.value = '';
            option.textContent = 'No active tenants';
            selector.appendChild(option);
            selector.disabled = true;
            return;
        }

        for (const tenant of availableTenants) {
            const option = document.createElement('option');
            option.value = tenant.tenantCode;
            option.textContent = `${tenant.tenantName} (${tenant.tenantCode})`;
            selector.appendChild(option);
        }

        selector.disabled = !uiTenantOverrideEnabled;
        if (state?.selectedTenantCode) {
            selector.value = state.selectedTenantCode;
        }
    };

    const reloadPageForTenantChange = tenantCode => {
        const url = new URL(window.location.href);

        if (tenantCode) {
            url.searchParams.set('tenantCode', tenantCode);
        } else {
            url.searchParams.delete('tenantCode');
        }

        window.location.assign(`${url.pathname}${url.search}${url.hash}`);
    };

    const emitTenantChange = () => {
        window.dispatchEvent(new CustomEvent('order-processing:tenant-changed', {
            detail: { ...state }
        }));
    };

    const resolveTenantCode = (payload, preferredTenantCode) => {
        const availableTenants = Array.isArray(payload?.availableTenants) ? payload.availableTenants : [];

        const preferredMatch = availableTenants.find(tenant =>
            typeof preferredTenantCode === 'string'
            && preferredTenantCode.length > 0
            && tenant.tenantCode.toLowerCase() === preferredTenantCode.toLowerCase());

        if (preferredMatch) {
            return preferredMatch.tenantCode;
        }

        if (payload?.activeTenantCode) {
            return payload.activeTenantCode;
        }

        return availableTenants[0]?.tenantCode || null;
    };

    const loadRuntimeConfiguration = async () => {
        if (!runtimeConfigurationUrl) {
            throw new Error('API base URL is not available in the UI layout.');
        }

        clearLegacyStoredTenantCode();

        const preferredTenantCode = getUrlTenantCode();
        const headers = {
            'Accept': 'application/json'
        };

        if (preferredTenantCode) {
            headers['X-Tenant-Code'] = preferredTenantCode;
        }

        const response = await fetch(runtimeConfigurationUrl, { headers });
        const payload = await response.json().catch(() => null);

        if (!response.ok || !payload?.activeTenantCode || !payload?.tenantHeaderName) {
            throw new Error(payload?.detail || payload?.message || 'Tenant unavailable');
        }

        const selectedTenantCode = resolveTenantCode(payload, preferredTenantCode);

        state = {
            apiBaseUrl,
            runtimeConfigurationUrl,
            tenantHeaderName: payload.tenantHeaderName,
            configuredActiveTenantCode: payload.configuredActiveTenantCode || payload.activeTenantCode,
            activeTenantCode: payload.activeTenantCode,
            selectedTenantCode,
            availableTenants: Array.isArray(payload.availableTenants) ? payload.availableTenants : []
        };

        stripTenantCodeFromUrl();
        syncSelector(state.availableTenants);
        setIndicatorState(`Tenant: ${selectedTenantCode || 'unavailable'}`, 'bg-primary');
        emitTenantChange();

        return state;
    };

    if (selector) {
        selector.addEventListener('change', event => {
            if (!uiTenantOverrideEnabled) {
                if (state?.selectedTenantCode) {
                    selector.value = state.selectedTenantCode;
                }

                return;
            }

            const selectedTenantCode = event.target.value || null;
            if (!state) {
                return;
            }

            if (selectedTenantCode === state.selectedTenantCode) {
                return;
            }

            state = {
                ...state,
                selectedTenantCode
            };

            setIndicatorState('Tenant: switching...', 'bg-dark');
            reloadPageForTenantChange(selectedTenantCode);
        });
    }

    return {
        ready() {
            if (!readyPromise) {
                setIndicatorState('Tenant: loading...', 'bg-dark');
                readyPromise = loadRuntimeConfiguration().catch(error => {
                    readyPromise = null;
                    setIndicatorState('Tenant: unavailable', 'bg-danger');
                    if (selector) {
                        selector.disabled = true;
                    }

                    throw error;
                });
            }

            return readyPromise;
        },
        getState() {
            return state;
        },
        getSelectedTenantCode() {
            return state?.selectedTenantCode || null;
        },
        getTenantHeaderName() {
            return state?.tenantHeaderName || 'X-Tenant-Code';
        }
    };
})();

window.OrderProcessingTenant.ready().catch(error => {
    console.error('Unable to load tenant configuration from API:', error);
});