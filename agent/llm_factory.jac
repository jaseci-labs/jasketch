"""LLM factory — creates a byllm Model with the user-supplied api_key and model name.

Pattern mirrors ProtoMCP/services/llm_factory.jac: callers store the returned
Model on the agent node and use  `by self.llm(...)`  so per-node credentials
are respected instead of falling back to the jac.toml default_llm singleton.
"""

import from byllm.lib { Model }

def create_llm(model_name: str, api_key: str) -> Model {
    name = model_name;
    # Anthropic models need the "anthropic/" LiteLLM prefix when no prefix is set
    if name.startswith("claude-") and not name.startswith("anthropic/") {
        name = f"anthropic/{name}";
    }
    # OpenAI models: well-known names (gpt-4o, gpt-4o-mini) are auto-detected,
    # but non-standard names (gpt-5.4-mini etc.) require explicit "openai/" prefix
    elif name.startswith("gpt-") and not name.startswith("openai/") {
        name = f"openai/{name}";
    }
    return Model(model_name=name, api_key=api_key);
}
