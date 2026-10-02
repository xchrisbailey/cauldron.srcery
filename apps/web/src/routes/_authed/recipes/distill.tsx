import * as stylex from "@stylexjs/stylex";
import { copy, type ImportJob, SourceUrl } from "@cauldron/shared";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { createFileRoute, Link } from "@tanstack/react-router";
import { Schema } from "effect";
import { type FormEvent, useState } from "react";
import { RecipeEditor } from "../../../components/editor/RecipeEditor";
import {
  Button,
  ButtonLink,
  FormMessage,
  Input,
  PageHeader,
  Skeleton,
  Textarea,
  useToast,
} from "../../../components/ui";
import { focusRing } from "../../../components/ui/controls";
import { cancelImport, importKeys, importQuery, startImport } from "../../../lib/imports";
import { failureOf } from "../../../lib/api-failure";
import { decodeRecipeForm, fromDraft, type RecipeFormValues } from "../../../lib/recipe-form";
import { useRecipeWrites } from "../../../lib/use-recipe-writes";
import { colors, fonts } from "../../../styles/tokens.stylex";
import { pageTitle } from "../../../lib/page-title";

// Distill (#13): a link or pasted text goes in on the left, and the draft
// recipe opens in the editor on the right with the fields to confirm in the
// Tips color. Nothing is saved until the cook saves it. The job id lives in
// the URL, so a reload picks the job back up.

const Search = Schema.toStandardSchemaV1(
  Schema.Struct({
    job: Schema.optional(Schema.String),
    /** "paste" opens the form on the paste box, after a link couldn't be read. */
    mode: Schema.optional(Schema.Literal("paste")),
  }),
);

export const Route = createFileRoute("/_authed/recipes/distill")({
  head: () => pageTitle(copy.imports.title),
  validateSearch: Search,
  component: Distill,
});

const isLink = Schema.is(SourceUrl);

function Distill() {
  const { job } = Route.useSearch();
  return job ? <Job key={job} id={job} /> : <Start />;
}

function Start() {
  const navigate = Route.useNavigate();
  const queryClient = useQueryClient();
  const { mode } = Route.useSearch();
  const [link, setLink] = useState("");
  const [text, setText] = useState("");
  const [linkError, setLinkError] = useState<string | undefined>();
  const [failed, setFailed] = useState(false);
  const [starting, setStarting] = useState(false);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    const url = link.trim();
    if (url !== "" && !isLink(url)) {
      setLinkError(copy.validation.link.text);
      return;
    }
    if (url === "" && text.trim() === "") return;
    setStarting(true);
    setFailed(false);
    try {
      const job = await startImport(url !== "" ? { url } : { text: text.trim() });
      queryClient.setQueryData(importKeys.detail(job.id), job);
      await navigate({ search: { job: job.id } });
    } catch (error) {
      setStarting(false);
      // A daily or per-minute limit says so in its own words.
      const failure = failureOf(error);
      if (failure.tag === "TooManyRequests") {
        setLinkError(failure.message);
        return;
      }
      setFailed(true);
    }
  };

  return (
    <>
      <PageHeader title={copy.imports.title.text} />
      <form onSubmit={(e) => void submit(e)} noValidate {...stylex.props(styles.start)}>
        {failed ? <FormMessage tone="error">{copy.imports.couldntStart.text}</FormMessage> : null}
        <Input
          label={copy.imports.link.text}
          name="url"
          type="url"
          inputMode="url"
          placeholder={copy.imports.linkPlaceholder.text}
          hint={copy.imports.linkHint.text}
          error={linkError}
          value={link}
          autoFocus={mode !== "paste"}
          autoComplete="off"
          onChange={(e) => {
            setLink(e.target.value);
            setLinkError(undefined);
          }}
        />
        <Textarea
          label={copy.imports.orPaste.text}
          name="text"
          hint={copy.imports.pasteHint.text}
          placeholder={copy.imports.pastePlaceholder.text}
          value={text}
          autoFocus={mode === "paste"}
          rows={12}
          disabled={link.trim() !== ""}
          onChange={(e) => setText(e.target.value)}
        />
        <div {...stylex.props(styles.row)}>
          <Button type="submit" disabled={starting || (link.trim() === "" && text.trim() === "")}>
            {starting ? copy.imports.distilling.text : copy.imports.distill.text}
          </Button>
        </div>
      </form>
    </>
  );
}

function Job({ id }: { id: string }) {
  const navigate = Route.useNavigate();
  const job = useQuery(importQuery(id));
  const again = () => void navigate({ search: {} });

  if (job.isPending) {
    return (
      <div aria-busy="true" aria-label={copy.ui.loading.text} {...stylex.props(styles.start)}>
        <Skeleton height={40} />
        <Skeleton width="60%" />
      </div>
    );
  }
  if (job.isError) {
    return (
      <>
        <PageHeader title={copy.imports.title.text} />
        <FormMessage tone="error">{copy.errors.notFound.text}</FormMessage>
        <div {...stylex.props(styles.row)}>
          <Button onClick={again}>{copy.imports.another.text}</Button>
        </div>
      </>
    );
  }

  const data = job.data;
  switch (data.status) {
    case "queued":
    case "running":
      return <Working job={data} />;
    case "done":
      // A draft that no longer reads (stored by an older version) can't be reviewed.
      return data.draft ? <Review job={data} /> : <Failed job={data} />;
    case "saved":
      return (
        <>
          <PageHeader title={copy.imports.title.text} />
          <FormMessage tone="info">{copy.imports.alreadySaved.text}</FormMessage>
          <div {...stylex.props(styles.row)}>
            {data.recipeId ? (
              <ButtonLink to="/recipes/$id" params={{ id: data.recipeId }}>
                {copy.imports.openDuplicate.text}
              </ButtonLink>
            ) : null}
            <Button variant="secondary" onClick={again}>
              {copy.imports.another.text}
            </Button>
          </div>
        </>
      );
    case "cancelled":
    case "failed":
      return <Failed job={data} />;
  }
}

function Failed({ job }: { job: ImportJob }) {
  const navigate = Route.useNavigate();
  return (
    <>
      <PageHeader title={copy.imports.title.text} />
      <FormMessage tone={job.status === "cancelled" ? "info" : "error"}>
        {job.status === "cancelled"
          ? copy.imports.stopped.text
          : (job.failure?.message ?? copy.imports.couldntRead.text)}
      </FormMessage>
      <div {...stylex.props(styles.row)}>
        {job.sourceUrl !== null ? (
          <Button onClick={() => void navigate({ search: { mode: "paste" } })}>
            {copy.imports.pasteInstead.text}
          </Button>
        ) : null}
        <Button variant="secondary" onClick={() => void navigate({ search: {} })}>
          {copy.imports.another.text}
        </Button>
      </div>
    </>
  );
}

/** The link, or a note that it was pasted, with the duplicate warning. */
function Source({ job }: { job: ImportJob }) {
  const link = job.draft?.sourceUrl ?? job.sourceUrl;
  const by = [job.draft?.siteName, job.draft?.sourceAuthor].filter(Boolean).join(" · ");
  return (
    <aside {...stylex.props(styles.source)}>
      <h2 {...stylex.props(styles.sourceTitle)}>{copy.imports.source.text}</h2>
      {link ? (
        <a
          href={link}
          target="_blank"
          rel="noreferrer"
          {...stylex.props(styles.link, focusRing.ring)}
        >
          {link}
        </a>
      ) : (
        <p {...stylex.props(styles.muted)}>{copy.imports.pasted.text}</p>
      )}
      {by ? <p {...stylex.props(styles.muted)}>{by}</p> : null}
      {job.duplicateOf ? (
        <div {...stylex.props(styles.duplicate)}>
          <p {...stylex.props(styles.duplicateText)}>
            {copy.imports.duplicate(job.duplicateOf.title).text} {copy.imports.saveAnyway.text}
          </p>
          <Link
            to="/recipes/$id"
            params={{ id: job.duplicateOf.id }}
            {...stylex.props(styles.link, focusRing.ring)}
          >
            {copy.imports.openDuplicate.text}
          </Link>
        </div>
      ) : null}
    </aside>
  );
}

function Working({ job }: { job: ImportJob }) {
  const queryClient = useQueryClient();
  const stop = async () => {
    try {
      queryClient.setQueryData(importKeys.detail(job.id), await cancelImport(job.id));
    } catch {
      // Still shown as running; the next poll says where it's at.
    }
  };
  return (
    <>
      <PageHeader
        title={copy.imports.title.text}
        actions={
          <Button variant="ghost" onClick={() => void stop()}>
            {copy.imports.stop.text}
          </Button>
        }
      />
      <div {...stylex.props(styles.layout)}>
        <Source job={job} />
        <div role="status" aria-busy="true" {...stylex.props(styles.working)}>
          <span aria-hidden="true" {...stylex.props(styles.dot)} />
          {copy.imports.distilling.text}
        </div>
      </div>
    </>
  );
}

function Review({ job }: { job: ImportJob }) {
  const navigate = Route.useNavigate();
  const writes = useRecipeWrites();
  const toast = useToast();
  // Read once: the draft doesn't change, and edits mustn't be reset.
  const [initial] = useState(() => fromDraft(job.draft!));

  const onSubmit = async (values: RecipeFormValues) => {
    const input = decodeRecipeForm(values);
    if (!input) return;
    try {
      const recipe = await writes.saveImport(job.id, input);
      await navigate({ to: "/recipes/$id", params: { id: recipe.id }, replace: true });
    } catch (error) {
      // Already saved (in another tab, say): the server's message says so.
      const conflict = failureOf(error).tag === "Conflict";
      toast(conflict ? copy.imports.alreadySaved.text : copy.editor.couldntSave.text, "error");
    }
  };

  const flagged =
    initial.review.length > 0 ||
    initial.ingredients.some((row) => row.flag) ||
    initial.steps.some((row) => row.flag);

  return (
    <div {...stylex.props(styles.layout)}>
      <div {...stylex.props(styles.wide)}>
        <Source job={job} />
      </div>
      <RecipeEditor
        title={copy.imports.title.text}
        initial={initial}
        // The draft stays on the job until it's saved; nothing to keep meanwhile.
        keep="none"
        onSubmit={onSubmit}
        intro={
          <>
            <div {...stylex.props(styles.narrow)}>
              <Source job={job} />
            </div>
            {flagged ? <FormMessage tone="info">{copy.imports.review.text}</FormMessage> : null}
          </>
        }
        actions={({ submit, submitting }) => (
          <>
            <Button variant="ghost" onClick={() => void navigate({ search: {} })}>
              {copy.imports.another.text}
            </Button>
            <Button onClick={submit} disabled={submitting}>
              {copy.editor.save.text}
            </Button>
          </>
        )}
      />
    </div>
  );
}

const desktop = "@media (min-width: 1100px)";

const styles = stylex.create({
  start: { display: "grid", gap: 16, maxWidth: 640 },
  row: { display: "flex", flexWrap: "wrap", gap: 8 },
  layout: {
    display: "grid",
    gap: 24,
    alignItems: "start",
    gridTemplateColumns: { default: "minmax(0, 1fr)", [desktop]: "260px minmax(0, 1fr)" },
  },
  // The source sits beside the editor on wide screens and under its header otherwise.
  wide: { display: { default: "none", [desktop]: "block" }, position: "sticky", top: 24 },
  narrow: { display: { default: "block", [desktop]: "none" } },
  source: {
    display: "grid",
    gap: 8,
    padding: 16,
    borderRadius: 14,
    backgroundColor: colors.mantle,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface0,
  },
  sourceTitle: { margin: 0, fontSize: 13, fontWeight: 600, color: colors.subtext },
  link: { color: colors.magic, overflowWrap: "anywhere", fontSize: 14 },
  muted: { margin: 0, fontSize: 13, color: colors.subtext },
  duplicate: {
    display: "grid",
    gap: 6,
    marginTop: 8,
    padding: 10,
    borderRadius: 10,
    backgroundColor: `color-mix(in srgb, ${colors.tips} 10%, transparent)`,
    outline: `1px solid color-mix(in srgb, ${colors.tips} 45%, transparent)`,
  },
  duplicateText: { margin: 0, fontSize: 13 },
  working: {
    display: "flex",
    alignItems: "center",
    gap: 10,
    minHeight: 120,
    paddingInline: 20,
    borderRadius: 14,
    borderWidth: 1,
    borderStyle: "dashed",
    borderColor: colors.surface1,
    color: colors.subtext,
    fontFamily: fonts.ui,
  },
  dot: {
    width: 9,
    height: 9,
    borderRadius: "50%",
    backgroundColor: colors.magic,
    animationName: stylex.keyframes({
      "0%": { opacity: 0.3 },
      "50%": { opacity: 1 },
      "100%": { opacity: 0.3 },
    }),
    animationDuration: { default: "1.4s", "@media (prefers-reduced-motion: reduce)": "0s" },
    animationIterationCount: "infinite",
  },
});
