import { Schema } from "effect";

export const UserId = Schema.String.pipe(Schema.brand("UserId"));
export type UserId = typeof UserId.Type;

export class User extends Schema.Class<User>("User")({
  id: UserId,
  email: Schema.String,
  name: Schema.String,
}) {}
