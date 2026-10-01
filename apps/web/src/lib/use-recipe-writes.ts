import { useQueryClient } from "@tanstack/react-query";
import { useMemo } from "react";
import { useToast } from "../components/ui";
import { makeRecipeWrites } from "./recipe-writes";
import { recipeApi } from "./recipes";

/** The recipe writes (recipe-writes.ts) over this app's QueryClient, the API and the toast. */
export function useRecipeWrites() {
  const cache = useQueryClient();
  const notify = useToast();
  return useMemo(() => makeRecipeWrites({ cache, api: recipeApi, notify }), [cache, notify]);
}
