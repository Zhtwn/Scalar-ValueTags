#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#ifdef HAVE_DMD_HELPER
#  define WANT_DMD_API_044
#  include "DMD_helper.h"
#endif

/* Back-compat for older perls
 * ---------------------------
 */

#ifndef av_push_simple
#  define av_push_simple(av, sv)  av_push(av, sv)
#endif

#ifndef av_count
#  define av_count(av) (AvFILL(av)+1)
#endif

#if defined(sv_magicv2_add)
#  define HAVE_VALUE_MAGIC
#endif

#ifdef HAVE_VALUE_MAGIC
#  define ENTER_DISARM_INFECT \
  ENTER;  \
  SAVESPTR(PL_viralmagic_annotations); PL_viralmagic_annotations = NULL

#define LEAVE_DISARM_INFECT  \
  LEAVE

/*** Structs ***/

struct ValueTagsUserStruct {
    SV *value_tags;
};

struct ValueTagsBehavior {
    SV*  (*make_tags)(pTHX);
    SV*  (*dup_tags)(pTHX_ SV *value_tags);
    void (*free_tags)(pTHX_ SV *sv, MAGIC *mg);   // FIXME: needed?
    void (*add_tag)(pTHX_ SV *sv, SV *tag);
    SV*  (*make_retval)(pTHX_ MAGIC *mg);
    void (*iter_begin)(pTHX_ SV *value_tags, void **ctx);
    SV*  (*iter_next)(pTHX_ SV *value_tags, void **ctx);
    void (*iter_end)(pTHX_ SV *value_tags, void **ctx);
};

struct ValueTagsSpec {
    struct ValueTagsSpec           *next;
    SV                             *vt_type;
    const struct ValueTagsBehavior *behavior;
};

#define VALUETAGS(mg) (MgUSERSTRUCT(mg, struct ValueTagsUserStruct *)->value_tags)

/*** UTILTIIES ***/

void av_append_uniq(pTHX_ SV *sav, SV *tag)
{
    assert(SvOK(sav) && SvTYPE(sav) == SVt_PVAV);
    assert(SvROK(tag));
    fprintf(stderr, ">av_append_uniq: 0x%x\n", tag);

    fprintf(stderr, "  casting to AV\n");
    AV *av = (AV *)sav;

    fprintf(stderr, "  AvARRAY\n");
    SV **svp = AvARRAY(av);
    fprintf(stderr, "  AvFILL\n");
    fprintf(stderr, "    MUTABLE_AV 0x%x\n", MUTABLE_AV(av));
    fprintf(stderr, "    AvFILLp 0x%x\n", AvFILLp(MUTABLE_AV(av)));
    fprintf(stderr, "  av_count\n");
    Size_t count = av_count(av);
    fprintf(stderr, "  scanning %u entries\n", count);
    for(U32 idx = 0; idx < av_count(av); idx++) {
        // Skip duplicates
        if(SvROK(svp[idx]) && SvRV(tag) == SvRV(svp[idx])) {
            return;
        }
    }

    fprintf(stderr, "  append new tag\n");
    fprintf(stderr, "  newSVsv\n");
    SV *ret = newSVsv(tag);
    fprintf(stderr, "  av_push_simple\n");
    av_push_simple(av, ret);

    fprintf(stderr, "<av_append_uniq\n");
    return;
}

void av_append(pTHX_ SV *sav, SV *tag)
{
    assert(SvOK(sav) && SvTYPE(sav) == SVt_PVAV);
    assert(tag);

    SV *new_tag = newSVsv(tag);
    av_push_simple((AV *)sav, new_tag);
    return;
}

void hv_inc_count(pTHX_ SV *shv, SV *tag)
{
    assert(SvOK(shv) && SvTYPE(shv) == SVt_PVHV);
    assert(tag);

    HV *hv = (HV *)shv;

    HE *he = hv_fetch_ent(hv, tag, FALSE, 0);
    if (he) {
        SV *val = hv_iterval(hv, he);
        SvIV_set(val, SvIV(val) + 1);
    }
    else {
        hv_store_ent(hv, tag, newSViv(1), 0);
    }

    return;
}

/*** FORWARD DECLARATIONS FOR MAGIC HANDLING ***/
#define get_value_tags_magic(vt_type, sv)  S_get_value_tags_magic(aTHX_ vt_type, sv)
static MAGIC *S_get_value_tags_magic(pTHX_ SV *vt_type, SV *sv);

#define add_value_tags_magic(vt_type, sv, value_tags)  S_add_value_tags_magic(aTHX_ vt_type, sv, value_tags)
static MAGIC *S_add_value_tags_magic(pTHX_ SV *vt_type, SV *sv, SV *value_tags);

#define init_value_tags_magic(vt_type, sv, value_tags)  S_init_value_tags_magic(aTHX_ vt_type, sv, value_tags)
static MAGIC *S_init_value_tags_magic(pTHX_ SV *vt_type, SV *sv, SV *value_tags);

#define remove_value_tags_magic(vt_type, sv)  S_remove_value_tags_magic(aTHX_ vt_type, sv)
static MAGIC *S_remove_value_tags_magic(pTHX_ SV *vt_type, SV *sv);

#define get_vt_spec(vt_type) S_get_vt_spec(aTHX_ vt_type)
static struct ValueTagsSpec *S_get_vt_spec(pTHX_ SV *vt_type);

/*** BEHAVIORS ***/

static SV *make_array_value_tags(pTHX)
{
    fprintf(stderr, ">make_array_value_tags\n");
    AV *av = newAV();
    fprintf(stderr, "<make_array_value_tags\n");
    return (SV *)av;
}

static SV *make_hash_value_tags(pTHX)
{
    fprintf(stderr, ">make_hash_value_tags\n");
    HV *hv = newHV();
    fprintf(stderr, "<make_hash_value_tags\n");
    return (SV *)hv;
}

static SV *dup_array_value_tags(pTHX_ SV *value_tags)
{
    assert(SvOK(value_tags) && SvTYPE(value_tags) == SVt_PVAV);
    return (SV *)newAVav((AV *)value_tags);
}

static SV *dup_hash_value_tags(pTHX_ SV *value_tags)
{
    assert(SvOK(value_tags) && SvTYPE(value_tags) == SVt_PVHV);
    return (SV *)newHVhv((HV *)value_tags);
}

static void free_value_tags(pTHX_ SV *sv, MAGIC *mg)
{
    assert(sv);
    assert(mg);     // FIXME - does magicv2 ever call this with NULL mg?
    fprintf(stderr, ">free_value_tags: sv: 0x%x\n", sv);
    fprintf(stderr, "  VALUETAGS\n");
    SV *vt = VALUETAGS(mg);
    if (vt) {
        fprintf(stderr, "  SvREFCNT_DEC\n");
        SvREFCNT_dec(vt);
        VALUETAGS(mg) = NULL;
    }
    fprintf(stderr, "<free_value_tags\n");
}

static SV *make_array_retval(pTHX_ MAGIC *mg)
{
    assert(mg);
    fprintf(stderr, ">make_array_retval\n");
    SV *vt = VALUETAGS(mg);
    assert(SvOK(vt) && SvTYPE(vt) == SVt_PVAV);

    AV *results = newAVav((AV *)vt);

    fprintf(stderr, "<make_array_retval: 0x%x\n", (SV *)results);
    return (SV *)results;
}

static SV *make_hash_retval(pTHX_ MAGIC *mg)
{
    assert(mg);

    SV *vt = VALUETAGS(mg);
    assert(SvOK(vt) && SvTYPE(vt) == SVt_PVAV);
    HV *results = newHVhv((HV *)vt);

    return (SV *)results;
}

void infect_value_tags(pTHX_ SV *osv, MAGIC *omg, SV *nsv, MAGIC *nmg)
{
    ENTER_DISARM_INFECT;    // DOCME: why is this required here?
    assert(osv);
    assert(omg);
    assert(nsv);

    fprintf(stderr, ">infect_value_tags: osv: 0x%x, nsv: 0x%x\n", osv, nsv);

    SV *vt_type = MgAUXSV(omg);
    struct ValueTagsSpec *vt_spec = get_vt_spec(vt_type);

    // nmg is never set, since MGv2f_SCALARVALUE_INFECTIOUS is not set
    nmg = get_value_tags_magic(vt_type, nsv);

    if (!nmg) {
        fprintf(stderr, "  dup_tags\n");
        SV *value_tags = vt_spec->behavior->dup_tags(aTHX_ VALUETAGS(omg));
        nmg = add_value_tags_magic(vt_type, nsv, value_tags);
        LEAVE_DISARM_INFECT;
        fprintf(stderr, "<infect_value_tags\n");
        return;
    }

    SV *ovt = VALUETAGS(omg);
    void *ctx;
    vt_spec->behavior->iter_begin(aTHX_ ovt, &ctx);
    SV *tag;
    fprintf(stderr, "  iter_next: ovt: 0x%x\n", ovt);
    while (tag = vt_spec->behavior->iter_next(aTHX_ ovt, &ctx)) {
        SV *foo = newSVsv(tag);
        vt_spec->behavior->add_tag(aTHX_ VALUETAGS(nmg), tag);
    }
    vt_spec->behavior->iter_end(aTHX_ ovt, &ctx);

#ifdef DEBUG_TRACE_ANNOTATIONS
        // FIXME: handle adding trace magic somewhere
        // copying existing annotation: sv will always have debug tracing
//      if(new) {
//          sv_magicext(new, (SV *)make_traceav_copy(svp[idx]), PERL_MAGIC_ext, &vtbl_hound_debugtrace, NULL, 0);
//      }
#endif

    LEAVE_DISARM_INFECT;
    fprintf(stderr, "<infect_value_tags\n");
}

static void iter_begin_array (pTHX_ SV *value_tags, void **ctx)
{
    assert(value_tags);
    assert(ctx);
    fprintf(stderr, ">iter_begin_array: vt: 0x%x, *ctx: 0x%x\n", value_tags, *ctx);
    AV *av = (AV *)value_tags;
    SSize_t *idx;
    Newx(idx, 1, SSize_t); // or Newxz?
    *idx = 0;
    *ctx = (void *)idx;
    fprintf(stderr, "<iter_begin_array: *idx: %d, *ctx: 0x%x\n", *idx, *ctx);
}

static SV *iter_next_array (pTHX_ SV *value_tags, void **ctx)
{
    assert(value_tags);
    assert(ctx);
    fprintf(stderr, ">iter_next_array: vt: 0x%x, *ctx: 0x%x\n", value_tags, *ctx);
    AV *av = (AV *)value_tags;
    SSize_t *idx = (SSize_t *)*ctx;
    fprintf(stderr, "  *idx: %d, av_count: %d\n", *idx, av_count(av));
    if (*idx >= av_count(av)) {
        fprintf(stderr, "  DONE\n");
        return NULL;
    }
    fprintf(stderr, "  av_fetch: idx: %d\n", *idx);
    SV **tag_ref = av_fetch(av, *idx, 0);
    if (!tag_ref)
        croak("iter_next_array: av_fetch returned null");
    fprintf(stderr, "    SvType(*tag_ref): %d\n", SvTYPE(*tag_ref));
    SV *tag = *tag_ref;
    fprintf(stderr, "  (*idx)++\n");
    (*idx)++;
    fprintf(stderr, "  tag: 0x%x\n", tag);
    fprintf(stderr, "<iter_next_array: *idx: %d **ctx: %d\n", *idx, *((SSize_t *)*ctx));
    return tag;
}

static void iter_end_array (pTHX_ SV *value_tags, void **ctx)
{
    assert(value_tags);
    assert(ctx);
    Safefree(*ctx);
}

static void iter_begin_hash (pTHX_ SV *value_tags, void **ctx)
{
    assert(value_tags);
    assert(ctx);
    HV *hv = (HV *)value_tags;

    // save hash count in ctx, to avoid calling hv_iternext on empty hash (FIXME: is this necessary?)
    I32 *cnt;
    Newx(cnt, 1, I32);
    *cnt = hv_iterinit(hv);
    *ctx = (void *)cnt;
};

static SV *iter_next_hash (pTHX_ SV *value_tags, void **ctx)
{
    assert(value_tags);
    assert(ctx);
    HV *hv = (HV *)value_tags;
    I32 *cnt = (I32 *)*ctx;

    if (!*cnt)
        return NULL;

    HE *he = hv_iternext(hv);

    if (!he)
        return NULL;

    return hv_iterval(hv, he);
}

static void iter_end_hash (pTHX_ SV *value_tags, void **ctx)
{
    assert(value_tags);
    assert(ctx);
    Safefree(*ctx);
}

enum behavior_types {
    BEHAVIOR_UNIQUE_REF_ARRAY,
    BEHAVIOR_APPEND_ARRAY,
    BEHAVIOR_HASH_COUNT,
    MAX_BEHAVIOR
};

static const struct ValueTagsBehavior behaviors[] = {
    [BEHAVIOR_UNIQUE_REF_ARRAY] = {
        .make_tags   = &make_array_value_tags,
        .dup_tags    = &dup_array_value_tags,
        .free_tags   = &free_value_tags,
        .make_retval = &make_array_retval,
        .add_tag     = &av_append_uniq,
        .iter_begin  = &iter_begin_array,
        .iter_next   = &iter_next_array,
        .iter_end    = &iter_end_array,
    },
    [BEHAVIOR_APPEND_ARRAY] = {
        .make_tags   = &make_array_value_tags,
        .dup_tags    = &dup_array_value_tags,
        .free_tags   = &free_value_tags,
        .make_retval = &make_array_retval,
        .add_tag     = &av_append,
        .iter_begin  = &iter_begin_array,
        .iter_next   = &iter_next_array,
        .iter_end    = &iter_end_array,
    },
    [BEHAVIOR_HASH_COUNT] = {
        .make_tags   = &make_hash_value_tags,
        .dup_tags    = &dup_hash_value_tags,
        .free_tags   = &free_value_tags,
        .make_retval = &make_hash_retval,
        .add_tag     = &hv_inc_count,
        .iter_begin  = &iter_begin_hash,
        .iter_next   = &iter_next_hash,
        .iter_end    = &iter_end_hash,
    },
};

/*** VALUE-TAGS SPECIFICATIONS ***/

static struct ValueTagsSpec *vt_specs = NULL;
static struct ValueTagsSpec *final_vt_spec = NULL;

static struct ValueTagsSpec *S_get_vt_spec(pTHX_ SV *vt_type)
{
    assert(vt_type);
    for (struct ValueTagsSpec *cur = vt_specs; cur; cur = cur->next) {
        if (cur && (cur->vt_type == vt_type)) {
            return cur;
        }
    }
//  croak("vt_type not registered");
    return NULL;
}

#define set_vt_type_behavior(vt_type, behavior_type) S_set_vt_type_behavior(aTHX_ vt_type, behavior_type)
static void S_set_vt_type_behavior(pTHX_ SV *vt_type, SV *behavior_type)
{
    assert(vt_type);
    assert(behavior_type);

    fprintf(stderr, ">S_set_vt_type_behavor\n");
    fprintf(stderr, "  behavior_type: %d\n", SvIV(behavior_type));
    const struct ValueTagsBehavior *behavior = &behaviors[SvIV(behavior_type)];
    fprintf(stderr, "  behavior: 0x%x\n", behavior);
    fprintf(stderr, "  behavior->make_tags: 0x%x\n", behavior->make_tags);

    struct ValueTagsSpec *new_vt_spec;
    Newx(new_vt_spec, 1, struct ValueTagsSpec);
    fprintf(stderr, "  new_vt_spec: 0x%x\n", new_vt_spec);
    *new_vt_spec = (struct ValueTagsSpec){
        .next     = NULL,
        .vt_type  = SvREFCNT_inc(vt_type),
        .behavior = behavior,
    };

    if (vt_specs) {
        final_vt_spec->next = new_vt_spec;
        final_vt_spec = new_vt_spec;
    }
    else {
        vt_specs      = new_vt_spec;
        final_vt_spec = new_vt_spec;
    }

    fprintf(stderr, "<set_vt_type_behavior\n");
}

/*** MAGIC ***/

static MAGIC *S_get_value_tags_magic(pTHX_ SV *vt_type, SV *sv)
{
    assert(vt_type);
    assert(sv);
    fprintf(stderr, ">S_get_value_tags_magic: sv: 0x%x\n", sv);

    MAGIC *mg = NULL;
    if (SvTYPE(sv) >=  SVt_PVMG) {
        mg = sv_magicv2_find_by_auxsv(sv, vt_type);
    }

    if (mg) fprintf(stderr, "<S_get_value_tags_magic: return magic\n"); else fprintf(stderr, "<S_get_value_tags_magic: NO magic\n");
    return mg;
}

static const struct ScalarValueMagicFunctions magic_funcs = {
    .ver       = 2,   /* Magic v2 */
    .shape     = MGv2s_SCALARVALUE,
    .free_mg   = &free_value_tags,
    .infect    = &infect_value_tags,
    .user_size = sizeof(struct ValueTagsUserStruct),
};

static MAGIC *S_add_value_tags_magic(pTHX_ SV *vt_type, SV *sv, SV *value_tags)
{
    assert(vt_type);
    assert(sv);
    assert(!get_value_tags_magic(vt_type, sv));

    fprintf(stderr, "<S_add_value_tags_magic\n");

    struct ValueTagsSpec *vt_spec = get_vt_spec(vt_type);

    // FIXME - detect and handle sv_magicv2_add failure?
    fprintf(stderr, "  sv_magicv2_add\n");
    MAGIC *mg = sv_magicv2_add(sv, (struct MagicFunctions *)&magic_funcs, 0, vt_type);

    // SvAUX refcnt is automatically decremented on mg destroy, so inc here
    SvREFCNT_inc(vt_type);

    if (!value_tags) {
        fprintf(stderr, "  make_tags\n");
        fprintf(stderr, "    vt_spec->behavior: 0x%x\n", vt_spec->behavior);
        fprintf(stderr, "    vt_spec->behavior->make_tags: 0x%x\n", vt_spec->behavior->make_tags);
        value_tags = vt_spec->behavior->make_tags(aTHX);
        fprintf(stderr, "  tags: 0x%x\n", value_tags);
    }

    fprintf(stderr, "  set VALUETAGS\n");
    VALUETAGS(mg) = value_tags;

    fprintf(stderr, "<S_add_value_tags_magic: return magic\n");
    return mg;
}

static MAGIC *S_init_value_tags_magic(pTHX_ SV *vt_type, SV *sv, SV *value_tags)
{
    assert(vt_type);
    assert(sv);
    fprintf(stderr, "<S_init_value_tags_magic\n");

    MAGIC *mg = get_value_tags_magic(vt_type, sv);

    if (!mg) {
        mg = add_value_tags_magic(vt_type, sv, value_tags);
    }

    fprintf(stderr, "<S_init_value_tags_magic: return magic\n");
    return mg;
}

static MAGIC *S_remove_value_tags_magic(pTHX_ SV *vt_type, SV *sv)
{
    assert(vt_type);
    assert(sv);
    fprintf(stderr, ">S_remove_value_tags_magic\n");

    fprintf(stderr, "  get_value_tags_magic\n");
    MAGIC *mg = get_value_tags_magic(vt_type, sv);

    if (mg) {
        fprintf(stderr, "  sv_magicv2_remove\n");
        sv_magicv2_remove(sv, mg);
    }

    // API FIXME - should remove_value_tags_magic return old magic???
    fprintf(stderr, "<S_remove_value_tags_magic\n");
    return mg;
}

#endif /* HAVE_VALUE_MAGIC */

/*** API ***/

MODULE = Scalar::ValueTags  PACKAGE = Scalar::ValueTags

int
SVTAGS_UNIQUE_REF_ARRAY()
  CODE:
    RETVAL = BEHAVIOR_UNIQUE_REF_ARRAY;
  OUTPUT:
    RETVAL

int
SVTAGS_APPEND_ARRAY()
  CODE:
    RETVAL = BEHAVIOR_APPEND_ARRAY;
  OUTPUT:
    RETVAL

int
SVTAGS_HASH_COUNT()
  CODE:
    RETVAL = BEHAVIOR_HASH_COUNT;
  OUTPUT:
    RETVAL

void
value_tags_enabled()
   CODE:
#ifdef HAVE_VALUE_MAGIC
    XSRETURN_YES;
#else
    XSRETURN_NO;
#endif

SV *
register_value_tags_type (SV *behavior)
  CODE:
#ifdef HAVE_VALUE_MAGIC
    fprintf(stderr, ">register_value_tags_type\n");
    if (!SvIOK(behavior))
      croak("Expected an integer for behavior");    // FIXME: need better error
    fprintf(stderr, "  behavior: %d\n", behavior);
    IV idx = SvIV(behavior);
    fprintf(stderr, "  idx: %d\n", idx);
    if (idx < 0 || idx >= MAX_BEHAVIOR)
      croak("Unknown behavior"); // FIXME: need better error

    SV *vt_type = newSV(0);
    fprintf(stderr, "  vt_type: 0x%x\n", vt_type);

    fprintf(stderr, "  set_vt_type_behavior\n");
    set_vt_type_behavior(vt_type, behavior);

    RETVAL = newRV(vt_type);
#else
    RETVAL = NULL;
#endif
  OUTPUT:
    RETVAL

void
add_value_tag (SV *vt_type_ref, SV *sv_ref, SV *tag)
  CODE:
#ifdef HAVE_VALUE_MAGIC
    if (!SvROK(vt_type_ref) || SvTYPE(SvRV(vt_type_ref)) > SVt_PVMG)
        croak("Expected a SCALAR reference for vt_type");   // FIXME - need better validation
    if (!SvROK(sv_ref) || SvTYPE(SvRV(sv_ref)) > SVt_PVMG)
        croak("Expected a SCALAR reference for target variable");
    fprintf(stderr, ">add_value_tag: sv: 0x%x, tag: 0x%x\n", SvRV(sv_ref), tag);

    // FIXME: add tag validation to vt_spec, and validate tag here

    SV *vt_type = SvRV(vt_type_ref);
    fprintf(stderr, "init_value_tags_magic: vt_type_ref: 0x%x, vt_type: 0x%x\n", vt_type_ref, vt_type);
    MAGIC *mg = init_value_tags_magic(vt_type, SvRV(sv_ref), NULL);
    if (mg) { fprintf(stderr, "  got mg\n"); } else { fprintf(stderr, "  NO mg\n"); }

    fprintf(stderr, "  get_vt_spec\n");
    struct ValueTagsSpec *vt_spec = get_vt_spec(vt_type);

    fprintf(stderr, "  vt_spec->behavior->add_tag\n");
    vt_spec->behavior->add_tag(aTHX_ VALUETAGS(mg), tag);

    fprintf(stderr, "<add_value_tag\n");
#endif

SV *
get_value_tags (SV *vt_type_ref, SV *sv_ref)
  CODE:
#ifdef HAVE_VALUE_MAGIC
    if (!SvROK(vt_type_ref) || SvTYPE(SvRV(vt_type_ref)) > SVt_PVMG)
        croak("Expected a SCALAR reference for vt_type");   // FIXME - need better validation
    if (!SvROK(sv_ref) || SvTYPE(SvRV(sv_ref)) > SVt_PVMG)
        croak("Expected a SCALAR reference for target variable");

    fprintf(stderr, ">get_value_tags: sv: 0x%x\n", SvIV(sv_ref));
    SV *vt_type = SvRV(vt_type_ref);
    fprintf(stderr, "  deref sv_ref\n");
    SV *sv = SvRV(sv_ref);
    fprintf(stderr, "  sv: 0x%x\n", sv);
    fprintf(stderr, "  vt_type: 0x%x\n", vt_type_ref);

    fprintf(stderr, "  get_value_tags_magic\n");
    MAGIC *mg = get_value_tags_magic(vt_type, sv);

    fprintf(stderr, "  get_vt_spec\n");
    struct ValueTagsSpec *vt_spec = get_vt_spec(vt_type);

    if (mg) {
        fprintf(stderr, "  has magic\n");
        RETVAL = newRV(vt_spec->behavior->make_retval(aTHX_ mg));
//      RETVAL = vt_spec->behavior->make_retval(aTHX_ mg);
    }
    else {
        fprintf(stderr, "  NO magic\n");
        RETVAL = NULL;
    }
#else
    fprintf(stderr, "  ValueTags not enabled\n");
    RETVAL = NULL;
#endif
    fprintf(stderr, "<get_value_tags: RETVAL: 0x%x\n", RETVAL);
  OUTPUT:
    RETVAL

void
clear_value_tags (SV *vt_type_ref, SV *sv_ref)
  CODE:
#ifdef HAVE_VALUE_MAGIC
    if (!SvROK(vt_type_ref) || SvTYPE(SvRV(vt_type_ref)) > SVt_PVMG)
        croak("Expected a SCALAR reference for vt_type");   // FIXME - need better validation
    if (!SvROK(sv_ref) || SvTYPE(SvRV(sv_ref)) > SVt_PVMG)
        croak("Expected a SCALAR reference for target variable");

    fprintf(stderr, ">clear_value_tags\n");
    SV *vt_type = SvRV(vt_type_ref);
    SV *sv = SvRV(sv_ref);
    fprintf(stderr, "  get_value_tags_magic\n");
    MAGIC *mg = get_value_tags_magic(vt_type, sv);

    if (mg) {
        fprintf(stderr, "  remove_value_tags_magic\n");
        remove_value_tags_magic(vt_type, sv);
    }

    fprintf(stderr, "<clear_value_tags\n");
#endif

