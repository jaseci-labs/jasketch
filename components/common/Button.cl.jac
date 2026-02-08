import from react { useState, useEffect }

def:pub Button(props: dict) -> any {
    label = props.label;
    title = props.title or label;
    variant = props.variant or "primary";
    
    primaryClasses = "bg-gradient-to-r from-violet-500 to-fuchsia-500 text-white shadow-lg shadow-violet-500/25 border-transparent";
    secondaryClasses = "bg-slate-700/50 text-slate-300 hover:bg-slate-700 hover:text-white border-slate-600";
    baseClasses = "px-4 py-2 text-lg rounded-xl border-2 cursor-pointer font-medium transition-all duration-200 hover:scale-105 active:scale-95";
    variantClasses = primaryClasses if variant == "primary" else secondaryClasses;

    return <button
        className={baseClasses + " " + variantClasses}
        onClick={props.onClick}
        title={title}
    >
        {label}
    </button>;
}

