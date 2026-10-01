import {
  GatherItem,
  GatherItemId,
  GatherItemInput,
  GatherItemUpdate,
  GatherList,
  LocalDate,
} from "@cauldron/shared";
import { HttpApiEndpoint, HttpApiGroup, OpenApi } from "effect/http-api";
import { Authorization } from "./Authorization.ts";
import { InvalidRequestError, NotFoundError } from "./errors.ts";

const week = { weekStart: LocalDate };
const item = { id: GatherItemId };

export class GatherApi extends HttpApiGroup.make("gather")
  .add(
    HttpApiEndpoint.get("week", "/:weekStart", {
      params: week,
      success: GatherList,
    }).annotate(
      OpenApi.Description,
      "The list for the seven days from `weekStart`, brought up to date with the week's plan first. Checks and items added by hand are kept; a gathered item is unchecked when the week needs more of it.",
    ),
    HttpApiEndpoint.post("add", "/:weekStart/items", {
      params: week,
      payload: GatherItemInput,
      success: GatherItem,
      error: InvalidRequestError,
    }).annotate(OpenApi.Description, "Adds an item by hand, read like an ingredient line."),
    HttpApiEndpoint.patch("update", "/items/:id", {
      params: item,
      payload: GatherItemUpdate,
      success: GatherItem,
      error: NotFoundError,
    }).annotate(
      OpenApi.Description,
      "Checks or unchecks an item, or marks it as in the pantry (remembered for that item in every week).",
    ),
    HttpApiEndpoint.delete("remove", "/items/:id", {
      params: item,
      success: GatherItem,
      error: [NotFoundError, InvalidRequestError],
    }).annotate(
      OpenApi.Description,
      "Removes an item added by hand. Gathered items follow the week's plan instead.",
    ),
  )
  .middleware(Authorization)
  .prefix("/gather")
  .annotateMerge(OpenApi.annotations({ title: "Gather list" })) {}
