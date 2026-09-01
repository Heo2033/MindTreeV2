import { invoke } from "@tauri-apps/api/core";
import { isTauriMode } from "./settings";

const LOCAL_SECRETS_PREFIX = "mindtree.secret.";

export async function storeKey(id: string, key: string): Promise<void> {
  if (isTauriMode()) {
    await invoke("store_secret", { key: `provider.${id}`, value: key });
  } else if (typeof localStorage !== "undefined") {
    localStorage.setItem(`${LOCAL_SECRETS_PREFIX}${id}`, key);
  }
}

export async function fetchKey(id: string): Promise<string | null> {
  if (isTauriMode()) {
    return invoke<string | null>("get_secret", { key: `provider.${id}` });
  }
  if (typeof localStorage === "undefined") return null;
  return localStorage.getItem(`${LOCAL_SECRETS_PREFIX}${id}`);
}

export async function forgetKey(id: string): Promise<void> {
  if (isTauriMode()) {
    await invoke("delete_secret", { key: `provider.${id}` });
  } else if (typeof localStorage !== "undefined") {
    localStorage.removeItem(`${LOCAL_SECRETS_PREFIX}${id}`);
  }
}