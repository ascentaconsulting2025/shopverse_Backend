import { Router } from "express";
import { z } from "zod";
import { supabaseAdmin } from "../../config/supabaseClient";
import { asyncHandler } from "../../utils/asyncHandler";
import { apiSuccess } from "../../utils/apiResponse";
import { ApiError } from "../../utils/apiError";
const router = Router();
const querySchema = z
  .object({
    category: z.string().max(200).optional(),
    subcategory: z.string().max(200).optional(),
    node: z.string().uuid().optional(),
    search: z.string().trim().max(100).optional(),
    seller: z.string().uuid().optional(),
    min: z.coerce.number().min(0).optional(),
    max: z.coerce.number().min(0).optional(),
    metal: z.string().max(500).optional(),
    purity: z.string().max(500).optional(),
    available: z.enum(["true", "false"]).optional(),
    sort: z
      .enum(["relevance", "price-asc", "price-desc", "newest"])
      .default("relevance"),
    page: z.coerce.number().int().min(1).max(10000).default(1),
    ids: z.string().max(4000).optional(),
  })
  .refine(
    (q) => q.min == null || q.max == null || q.min <= q.max,
    "Invalid price range",
  );
router.get(
  "/categories",
  asyncHandler(async (req, res) => {
    const { data, error } = await supabaseAdmin.rpc(
      z
        .enum(["product", "service"])
        .default("product")
        .parse(req.query.kind) === "service"
        ? "explore_service_facets"
        : "explore_facets",
    );
    if (error)
      throw new ApiError(
        "The catalog is temporarily unavailable. Please try again.",
        503,
      );
    res.json(apiSuccess(data));
  }),
);
for (const kind of ["products", "services"] as const) {
  router.get(
    `/${kind}`,
    asyncHandler(async (req, res) => {
      const q = querySchema.parse(req.query);
      let query = supabaseAdmin
        .from(kind === "services" ? "explore_services" : "explore_products")
        .select("*", { count: "exact" });
      if (q.category) query = query.eq("category", q.category);
      if (q.subcategory) query = query.eq("subcategory", q.subcategory);
      // The SDK encodes JS arrays as PostgreSQL arrays; category_path is JSONB.
      if (q.node) query = query.contains("category_path", JSON.stringify([{id:q.node}]));
      if (q.search)
        query = query.ilike("name", `%${q.search.replace(/[\\%_]/g, "\\$&")}%`);
      if (kind === "products" && q.metal)
        query = query.eq("specifications->>Metal", q.metal);
      if (kind === "products" && q.purity)
        query = query.eq("specifications->>Purity", q.purity);
      if (q.seller) query = query.eq("business_id", q.seller);
      if (q.min != null) query = query.gte("price", q.min);
      if (q.max != null) query = query.lte("price", q.max);
      if (kind === "products" && q.available)
        query = query.eq("available", q.available === "true");
      if (q.ids)
        query = query.in(
          "id",
          z.array(z.string().uuid()).max(100).parse(q.ids.split(",")),
        );
      if (q.sort.startsWith("price"))
        query = query.order("price", {
          ascending: q.sort === "price-asc",
          nullsFirst: false,
        });
      else
        query = query.order(q.sort === "newest" ? "created_at" : "sort_order", {
          ascending: q.sort !== "newest",
        });
      const { data, error, count } = await query
        .order("id")
        .range((q.page - 1) * 24, q.page * 24 - 1);
      if (error) throw new ApiError(`Unable to load ${kind}`, 503);
      res.json(apiSuccess({ items: data, total: count, page: q.page }));
    }),
  );
  router.get(
    `/${kind}/:id`,
    asyncHandler(async (req, res) => {
      const id = z.string().uuid().parse(req.params.id);
      const { data, error } = await supabaseAdmin
        .from(kind === "services" ? "explore_services" : "explore_products")
        .select("*")
        .eq("id", id)
        .maybeSingle();
      if (error)
        throw new ApiError(
          `Unable to load ${kind === "services" ? "service" : "product"}`,
          503,
        );
      if (!data)
        throw new ApiError(
          `This ${kind === "services" ? "service" : "product"} is no longer available`,
          404,
        );
      res.json(apiSuccess(data));
    }),
  );
}
export default router;
