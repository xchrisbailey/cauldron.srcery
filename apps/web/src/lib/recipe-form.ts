import {
  detectTimer,
  isSectionHeading,
  parseIngredientLine,
  type ParsedIngredient,
  type Recipe,
  RecipeInput,
  type SourcePlatform,
} from "@cauldron/shared";
import { Schema } from "effect";

// The editor's form model and its mapping to the API's RecipeInput. The form
// keeps what the cook typed (ingredient lines, section headings, number fields
// as text); `toRecipeInput` turns it into the shared schema's shape, and
// `validateRecipeForm` checks it with that schema through Standard Schema.

export interface IngredientRow {
  readonly key: string;
  readonly kind: "line";
  /** The line as typed. */
  readonly text: string;
  /** What the parser read from `text`, or the cook's correction of it. */
  readonly parsed: ParsedIngredient;
  /** The cook changed `parsed` by hand; retyping the line resets it. */
  readonly corrected: boolean;
  /** Why an import wants this line looked at, shown in the Tips color. */
  readonly flag: string | null;
}

export interface HeadingRow {
  readonly key: string;
  readonly kind: "heading";
  readonly text: string;
  readonly flag: string | null;
}

export type IngredientFormRow = IngredientRow | HeadingRow;

export interface StepRow {
  readonly key: string;
  readonly text: string;
  readonly section: string | null;
  readonly timerSeconds: number | null;
  /** The cook set or cleared the timer, so it no longer follows the text. */
  readonly timerSet: boolean;
  readonly flag: string | null;
}

/** Top-level fields an import can flag for a second look. */
export type ReviewField =
  | "title"
  | "description"
  | "servings"
  | "prepMinutes"
  | "cookMinutes"
  | "totalMinutes"
  | "sourceUrl"
  | "tags"
  | "notes";

export interface RecipeFormValues {
  title: string;
  description: string;
  servings: string;
  prepMinutes: string;
  cookMinutes: string;
  totalMinutes: string;
  sourceUrl: string;
  notes: string;
  tags: Array<string>;
  ingredients: Array<IngredientFormRow>;
  steps: Array<StepRow>;
  /** Kept from the recipe or the import; not edited here. */
  sourcePlatform: SourcePlatform;
  sourceAuthor: string | null;
  /** Fields still flagged for a look. A field drops off when it's edited. */
  review: Array<ReviewField>;
}

let counter = 0;
/** A stable key for a new row, unique within the page. */
export const rowKey = () => `r${Date.now().toString(36)}${(counter++).toString(36)}`;

export const ingredientRow = (text: string, flag: string | null = null): IngredientFormRow =>
  isSectionHeading(text)
    ? { key: rowKey(), kind: "heading", text: headingText(text), flag }
    : {
        key: rowKey(),
        kind: "line",
        text,
        parsed: parseIngredientLine(text),
        corrected: false,
        flag,
      };

export const stepRow = (text: string, flag: string | null = null): StepRow => ({
  key: rowKey(),
  text,
  section: null,
  timerSeconds: detectTimer(text),
  timerSet: false,
  flag,
});

/** "For the sauce:" reads as the heading "For the sauce". */
const headingText = (line: string) =>
  line
    .trim()
    .replace(/^[-•*▢□]\s*/, "")
    .replace(/:$/, "")
    .trim();

export const emptyRecipeForm = (): RecipeFormValues => ({
  title: "",
  description: "",
  servings: "",
  prepMinutes: "",
  cookMinutes: "",
  totalMinutes: "",
  sourceUrl: "",
  notes: "",
  tags: [],
  ingredients: [ingredientRow("")],
  steps: [stepRow("")],
  sourcePlatform: "manual",
  sourceAuthor: null,
  review: [],
});

const text = (value: number | null) => (value === null ? "" : String(value));

const sameParse = (a: ParsedIngredient, b: ParsedIngredient) =>
  JSON.stringify([a.quantity, a.unit, a.item, a.note, a.optional, a.alt]) ===
  JSON.stringify([b.quantity, b.unit, b.item, b.note, b.optional, b.alt]);

export const fromRecipe = (recipe: Recipe): RecipeFormValues => {
  const ingredients: Array<IngredientFormRow> = [];
  let section: string | null = null;
  for (const line of recipe.ingredients) {
    if (line.section !== section) {
      section = line.section;
      if (section !== null)
        ingredients.push({ key: rowKey(), kind: "heading", text: section, flag: null });
    }
    const parsed: ParsedIngredient = {
      quantity: line.quantity,
      unit: line.unit,
      item: line.item,
      note: line.note,
      optional: line.optional,
      alt: line.alt,
      original: line.original,
    };
    ingredients.push({
      key: rowKey(),
      kind: "line",
      text: line.original,
      parsed,
      corrected: !sameParse(parsed, parseIngredientLine(line.original)),
      flag: null,
    });
  }
  return {
    title: recipe.title,
    description: recipe.description ?? "",
    servings: text(recipe.servings),
    prepMinutes: text(recipe.prepMinutes),
    cookMinutes: text(recipe.cookMinutes),
    totalMinutes: text(recipe.totalMinutes),
    sourceUrl: recipe.sourceUrl ?? "",
    notes: recipe.notes ?? "",
    tags: recipe.tags.map((tag) => tag.name),
    ingredients: ingredients.length > 0 ? ingredients : [ingredientRow("")],
    steps:
      recipe.steps.length > 0
        ? recipe.steps.map((step) => ({
            key: rowKey(),
            text: step.text,
            section: step.section,
            timerSeconds: step.timerSeconds,
            timerSet: step.timerSeconds !== detectTimer(step.text),
            flag: null,
          }))
        : [stepRow("")],
    sourcePlatform: recipe.sourcePlatform,
    sourceAuthor: recipe.sourceAuthor,
    review: [],
  };
};

/** Blank is null; anything else must be a number (the schema rejects NaN and fractions). */
const number = (value: string): number | null =>
  value.trim() === "" ? null : Number(value.trim());

/**
 * The form as a RecipeInput (still unvalidated). Blank lines and steps are
 * dropped; headings become the `section` of the lines under them. `rowOf`
 * maps each ingredient's index in the input back to its row in the form.
 */
export const toRecipeInput = (values: RecipeFormValues) => {
  const ingredients: Array<Record<string, unknown>> = [];
  const rowOf: Array<number> = [];
  let section: string | null = null;
  values.ingredients.forEach((row, index) => {
    if (row.kind === "heading") {
      section = row.text.trim() || null;
      return;
    }
    if (row.text.trim() === "") return;
    ingredients.push({ ...row.parsed, section, original: row.text.trim() });
    rowOf.push(index);
  });
  const stepOf: Array<number> = [];
  const steps = values.steps.flatMap((step, index) => {
    if (step.text.trim() === "") return [];
    stepOf.push(index);
    return [{ section: step.section, text: step.text, timerSeconds: step.timerSeconds }];
  });
  const input = {
    title: values.title,
    description: values.description,
    servings: number(values.servings),
    prepMinutes: number(values.prepMinutes),
    cookMinutes: number(values.cookMinutes),
    totalMinutes: number(values.totalMinutes),
    sourcePlatform: values.sourcePlatform,
    sourceUrl: values.sourceUrl.trim() === "" ? null : values.sourceUrl,
    sourceAuthor: values.sourceAuthor,
    notes: values.notes,
    tags: values.tags,
    ingredients,
    steps,
  };
  return { input, rowOf, stepOf };
};

const standard = Schema.toStandardSchemaV1(RecipeInput)["~standard"];

export type RecipeFormErrors = Record<string, string>;

/**
 * Validates the form against the shared RecipeInput schema and returns errors
 * keyed by form field name (`title`, `ingredients[3]`, `steps[0]`), or an
 * empty object when it's valid.
 */
export const validateRecipeForm = (values: RecipeFormValues): RecipeFormErrors => {
  const { input, rowOf, stepOf } = toRecipeInput(values);
  const result = standard.validate(input);
  if (result instanceof Promise || !result.issues) return {};
  const errors: RecipeFormErrors = {};
  for (const issue of result.issues) {
    const path = (issue.path ?? []).map((segment) =>
      typeof segment === "object" && segment !== null && "key" in segment ? segment.key : segment,
    );
    const [head, index] = path;
    let name = String(head ?? "title");
    if (head === "ingredients" && typeof index === "number") {
      name = `ingredients[${rowOf[index]}]`;
    } else if (head === "steps" && typeof index === "number") {
      name = `steps[${stepOf[index]}]`;
    }
    // The shared schemas carry plain messages from copy.validation.
    errors[name] ??= issue.message;
  }
  return errors;
};

/** The validated input to send, or null when the form has errors. */
export const decodeRecipeForm = (values: RecipeFormValues): RecipeInput | null => {
  const decoded = Schema.decodeUnknownOption(RecipeInput)(toRecipeInput(values).input);
  return decoded._tag === "Some" ? decoded.value : null;
};

// ---------------------------------------------------------------------------
// Pasting

const BULLET = /^\s*(?:[-•*▢□◦‣]|\d+[.)]|step\s+\d+[.:)]?)\s*/i;

/** Splits a pasted ingredient block into lines, dropping blanks and bullets. */
export const splitIngredientPaste = (pasted: string): Array<string> =>
  pasted
    .split(/\r?\n/)
    .map((line) => line.replace(/^\s*[-•*▢□◦‣]\s*/, "").trim())
    .filter((line) => line !== "");

/**
 * Splits a pasted method into steps: by blank lines when there are any,
 * otherwise one step per line. Leading numbers ("1.", "Step 2:") go.
 */
export const splitStepPaste = (pasted: string): Array<string> => {
  const normalized = pasted.replace(/\r\n/g, "\n").trim();
  const chunks = /\n\s*\n/.test(normalized) ? normalized.split(/\n\s*\n/) : normalized.split("\n");
  return chunks
    .map((chunk) =>
      chunk
        .replace(/\s*\n\s*/g, " ")
        .replace(BULLET, "")
        .trim(),
    )
    .filter((chunk) => chunk !== "");
};

/** Reads a quantity the cook typed ("1 1/2", "½", "2-3") with the shared parser. */
export const parseQuantity = (value: string): ParsedIngredient["quantity"] | "invalid" => {
  if (value.trim() === "") return null;
  const parsed = parseIngredientLine(`${value.trim()} x`);
  return parsed.quantity !== null && parsed.item === "x" ? parsed.quantity : "invalid";
};
