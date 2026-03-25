def:pub ChatSettings(props: dict) -> JsxElement {
    currentSettings = props.settings or {"apiKey": "", "model": "gpt-4o", "provider": "openai"};
    onSave = props.onSave;
    onClose = props.onClose;

    has provider: str = currentSettings.provider or "openai";
    has model: str = currentSettings.model or "gpt-4o";
    has apiKey: str = currentSettings.apiKey or "";

    PROVIDERS = [
        {"id": "openai", "label": "OpenAI", "models": ["gpt-4o", "gpt-4o-mini", "o1", "o3-mini"]},
        {"id": "anthropic", "label": "Anthropic", "models": ["claude-sonnet-4-20250514", "claude-opus-4-20250514", "claude-haiku-4-5-20251001"]},
        {"id": "google", "label": "Google", "models": ["gemini/gemini-2.0-flash", "gemini/gemini-2.5-pro"]},
        {"id": "custom", "label": "Custom", "models": []}
    ];

    def getModelsForProvider(providerId: str) -> list {
        pi = 0;
        while pi < PROVIDERS.length {
            if PROVIDERS[pi].id == providerId {
                return PROVIDERS[pi].models;
            }
            pi = pi + 1;
        }
        return [];
    }

    def handleProviderChange(e: any) -> None {
        newProvider = e.target.value;
        provider = newProvider;
        providerModels = getModelsForProvider(newProvider);
        if providerModels.length > 0 {
            model = providerModels[0];
        }
    }

    def handleSave() -> None {
        onSave({
            "provider": provider,
            "model": model,
            "apiKey": apiKey
        });
        onClose();
    }

    providerModels = getModelsForProvider(provider);

    return <div className="border-b border-gray-200/60 bg-gray-50/50 px-3 py-3 animate-fade-in">
        <div className="space-y-2.5">
            <div>
                <span className="sidebar-label">Provider</span>
                <select
                    value={provider}
                    onChange={handleProviderChange}
                    onKeyDown={lambda e: any -> None { e.stopPropagation(); }}
                    className="w-full mt-1 rounded-md border border-gray-200 px-2 py-1.5 text-xs bg-white focus:outline-none focus:ring-2 focus:ring-orange-500/50"
                >
                    {[
                        <option key={p.id} value={p.id}>{p.label}</option>
                        for p in PROVIDERS
                    ]}
                </select>
            </div>

            <div>
                <span className="sidebar-label">Model</span>
                {providerModels.length > 0 and
                    <div className="mt-1">
                        <select
                            value={model}
                            onChange={lambda e: any -> None { model = e.target.value; }}
                            onKeyDown={lambda e: any -> None { e.stopPropagation(); }}
                            className="w-full rounded-md border border-gray-200 px-2 py-1.5 text-xs bg-white focus:outline-none focus:ring-2 focus:ring-orange-500/50"
                        >
                            {[
                                <option key={m} value={m}>{m}</option>
                                for m in providerModels
                            ]}
                        </select>
                        <input
                            type="text"
                            value={model}
                            onInput={lambda e: any -> None { model = e.target.value; }}
                            onKeyDown={lambda e: any -> None { e.stopPropagation(); }}
                            placeholder="Or type custom model name..."
                            className="w-full mt-1 rounded-md border border-gray-200 px-2 py-1.5 text-xs bg-white focus:outline-none focus:ring-2 focus:ring-orange-500/50"
                        />
                    </div>
                or
                    <input
                        type="text"
                        value={model}
                        onInput={lambda e: any -> None { model = e.target.value; }}
                        onKeyDown={lambda e: any -> None { e.stopPropagation(); }}
                        placeholder="Enter model name (e.g. gpt-4o)"
                        className="w-full mt-1 rounded-md border border-gray-200 px-2 py-1.5 text-xs bg-white focus:outline-none focus:ring-2 focus:ring-orange-500/50"
                    />
                }
            </div>

            <div>
                <span className="sidebar-label">API Key</span>
                <input
                    type="password"
                    value={apiKey}
                    onInput={lambda e: any -> None { apiKey = e.target.value; }}
                    onKeyDown={lambda e: any -> None { e.stopPropagation(); }}
                    placeholder="sk-..."
                    className="w-full mt-1 rounded-md border border-gray-200 px-2 py-1.5 text-xs bg-white focus:outline-none focus:ring-2 focus:ring-orange-500/50"
                />
            </div>

            <button
                onClick={handleSave}
                className="w-full rounded-md bg-orange-500 hover:bg-orange-600 text-white text-xs font-medium py-1.5 transition-colors"
            >
                {"Save Settings"}
            </button>
        </div>
    </div>;
}
