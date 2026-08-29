"""JaSketch scene encryption and sharing service using Web Crypto API.

Client-side AES-GCM 128-bit encryption for scene snapshots.
All keys live in URL hash only — server never sees them.
"""

sv import from .sharing { create_share, read_share, ShareRef, SharePayload }

glob SHARE_KEY_LENGTH: int = 128;    # AES-GCM 128-bit
glob SHARE_IV_LENGTH: int = 12;      # bytes

"""Check if Web Crypto API is available (requires HTTPS or localhost)."""
def:pub check_crypto_available() -> bool {
    try {
        return window.crypto and window.crypto.subtle;
    } except Exception {
        return False;
    }
}

"""Generate random AES-GCM 128-bit key, return as base64url."""
async def:pub generate_encryption_key() -> str {
    try {
        key: any = await window.crypto.subtle.generateKey(
            {"name": "AES-GCM", "length": 128},
            True,
            ["encrypt", "decrypt"]
        );

        raw_key: any = await window.crypto.subtle.exportKey("raw", key);
        key_bytes = Array.from(new(Uint8Array, raw_key));
        key_b64 = btoa(String.fromCharCode.apply(None, key_bytes));
        # base64 -> base64url
        return key_b64.replace(RegExp("\\+", "g"), "-").replace(RegExp("\\/", "g"), "_").replace(RegExp("=", "g"), "");
    } except Exception as e {
        console.error("Failed to generate encryption key:", e);
        return "";
    }
}

"""Encrypt scene elements array as JSON using AES-GCM, return base64url(iv||ciphertext)."""
async def:pub encrypt_scene(elements: list, key_b64: str) -> str {
    try {
        # Decode base64url key
        key_b64_padded = key_b64 + ("=" * (4 - (len(key_b64) % 4)));
        key_b64_std = key_b64_padded.replace("-", "+").replace("_", "/");
        key_bytes_b64 = atob(key_b64_std);
        key_bytes = new(Uint8Array, len(key_bytes_b64));
        i = 0;
        while i < len(key_bytes_b64) {
            key_bytes[i] = key_bytes_b64.charCodeAt(i);
            i = i + 1;
        }

        key: any = await window.crypto.subtle.importKey(
            "raw",
            key_bytes,
            "AES-GCM",
            False,
            ["encrypt", "decrypt"]
        );

        # Generate random IV
        iv = window.crypto.getRandomValues(new(Uint8Array, SHARE_IV_LENGTH));

        # Serialize and encode plaintext
        json_str = JSON.stringify(elements);
        plaintext = new(TextEncoder).encode(json_str);

        # Encrypt
        ciphertext: any = await window.crypto.subtle.encrypt(
            {"name": "AES-GCM", "iv": iv},
            key,
            plaintext
        );

        # Combine iv || ciphertext
        combined = new(Uint8Array, iv.length + ciphertext.byteLength);
        combined.set(new(Uint8Array, iv), 0);
        combined.set(new(Uint8Array, ciphertext), iv.length);

        # Convert to base64url
        combined_b64 = btoa(String.fromCharCode.apply(None, Array.from(combined)));
        return combined_b64.replace(RegExp("\\+", "g"), "-").replace(RegExp("\\/", "g"), "_").replace(RegExp("=", "g"), "");
    } except Exception as e {
        console.error("Failed to encrypt scene:", e);
        return "";
    }
}

"""Decrypt base64url(iv||ciphertext) using AES-GCM, return elements array."""
async def:pub decrypt_scene(ciphertext_b64url: str, key_b64: str) -> list {
    try {
        # Decode base64url key
        key_b64_padded = key_b64 + ("=" * (4 - (len(key_b64) % 4)));
        key_b64_std = key_b64_padded.replace("-", "+").replace("_", "/");
        key_bytes_b64 = atob(key_b64_std);
        key_bytes = new(Uint8Array, len(key_bytes_b64));
        ki = 0;
        while ki < len(key_bytes_b64) {
            key_bytes[ki] = key_bytes_b64.charCodeAt(ki);
            ki = ki + 1;
        }

        key: any = await window.crypto.subtle.importKey(
            "raw",
            key_bytes,
            "AES-GCM",
            False,
            ["encrypt", "decrypt"]
        );

        # Decode ciphertext from base64url
        ciphertext_b64_std = ciphertext_b64url.replace("-", "+").replace("_", "/");
        padding_len = 4 - (len(ciphertext_b64_std) % 4);
        if padding_len != 4 {
            ciphertext_b64_std = ciphertext_b64_std + ("=" * padding_len);
        }
        combined_str = atob(ciphertext_b64_std);
        combined_bytes = new(Uint8Array, len(combined_str));
        ci = 0;
        while ci < len(combined_str) {
            combined_bytes[ci] = combined_str.charCodeAt(ci);
            ci = ci + 1;
        }

        # Extract iv and ciphertext
        iv = combined_bytes.slice(0, SHARE_IV_LENGTH);
        ciphertext = combined_bytes.slice(SHARE_IV_LENGTH);

        # Decrypt
        plaintext_buffer: any = await window.crypto.subtle.decrypt(
            {"name": "AES-GCM", "iv": iv},
            key,
            ciphertext
        );

        plaintext_str = new(TextDecoder).decode(plaintext_buffer);
        elements = JSON.parse(plaintext_str);
        return elements;
    } except Exception as e {
        console.error("Failed to decrypt scene:", e);
        return [];
    }
}

"""Encrypt the scene client-side and store the ciphertext; returns {share_id, key}."""
async def:pub export_to_share_backend(elements: list) -> dict {
    try {
        # Generate encryption key
        key = await generate_encryption_key();
        if not key {
            return {"error": "Failed to generate encryption key"};
        }

        # Encrypt scene
        ciphertext = await encrypt_scene(elements, key);
        if not ciphertext {
            return {"error": "Failed to encrypt scene"};
        }

        ref: ShareRef = await create_share(ciphertext);
        if ref.error {
            return {"error": ref.error};
        }
        return {"share_id": ref.share_id, "key": key};
    } except Exception as e {
        console.error("Failed to export to share backend:", e);
        return {"error": str(e)};
    }
}

"""Load a stored scene by id and decrypt it locally; returns {ok, elements, error}."""
async def:pub import_from_share_backend(share_id: str, key: str) -> dict {
    try {
        payload: SharePayload = await read_share(share_id);
        if payload.error {
            return {"ok": False, "elements": [], "error": payload.error};
        }
        ciphertext = payload.ciphertext;
        if not ciphertext {
            return {"ok": False, "elements": [], "error": "Share data is empty or corrupted"};
        }

        elements = await decrypt_scene(ciphertext, key);
        if elements is None {
            return {"ok": False, "elements": [], "error": "Failed to decrypt share — the link may be incomplete"};
        }
        return {"ok": True, "elements": elements, "error": ""};
    } except Exception as e {
        console.error("Failed to import from share backend:", e);
        return {"ok": False, "elements": [], "error": "Unexpected error loading share"};
    }
}

"""Generate room_id (20 hex chars) and room_key."""
def:pub generate_room_credentials() -> dict {
    try {
        # Generate 20 hex characters for room_id
        room_id = "";
        hex_chars = "0123456789abcdef";
        i = 0;
        while i < 20 {
            room_id = room_id + hex_chars[Math.floor(Math.random() * 16)];
            i = i + 1;
        }

        # For MVP: room_key is same as room_id
        room_key = room_id;

        return {"room_id": room_id, "room_key": room_key};
    } except Exception as e {
        console.error("Failed to generate room credentials:", e);
        return {};
    }
}
