import { describe, expect, it } from "vite-plus/test";
import { ingredientKey, stepIngredients } from "../src/index.ts";

const ingredients = (...items: ReadonlyArray<string>) =>
  items.map((item) => ({ itemKey: ingredientKey(item) }));

describe("stepIngredients", () => {
  it("finds ingredients named in full, plural or singular", () => {
    const list = ingredients("olive oil", "onions", "garlic", "chili flakes");
    const steps = [
      { text: "Warm the olive oil and soften the onion." },
      { text: "Stir in the garlic and chili flake." },
      { text: "Serve." },
    ];
    expect(stepIngredients(steps, list)).toEqual([[0, 1], [2, 3], []]);
  });

  it("matches the last word of a longer item", () => {
    const list = ingredients("red bell pepper", "crushed tomatoes");
    expect(stepIngredients([{ text: "Add the pepper, then the tomatoes." }], list)).toEqual([
      [0, 1],
    ]);
  });

  it("prefers an item named in full over others that share its last word", () => {
    const list = ingredients("red bell pepper", "black pepper");
    expect(stepIngredients([{ text: "Season with black pepper." }], list)).toEqual([[1]]);
  });

  it("doesn't match vague last words on their own", () => {
    const list = ingredients("lemon juice", "chicken stock");
    expect(stepIngredients([{ text: "Add the juice and the stock." }], list)).toEqual([[]]);
    expect(stepIngredients([{ text: "Add the lemon juice and the chicken stock." }], list)).toEqual(
      [[0, 1]],
    );
  });

  it("ignores case and punctuation", () => {
    const list = ingredients("Eggs");
    expect(stepIngredients([{ text: "Crack in the EGGS!" }], list)).toEqual([[0]]);
  });
});
