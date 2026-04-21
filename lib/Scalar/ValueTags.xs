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

#  define LEAVE_DISARM_INFECT \
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
    void (*iter_begin)(pTHX_ SV *value_tags, void **iter_cxt);
    SV*  (*iter_next)(pTHX_ SV *value_tags, void **iter_cxt);
    void (*iter_end)(pTHX_ SV *value_tags, void **iter_cxt);
};

struct ValueTagsSpec {
    struct ValueTagsSpec           *next;
    SV                             *vt_type;
    const struct ValueTagsBehavior *behavior;
};

#define VALUETAGS(mg) (MgUSERSTRUCT(mg, struct ValueTagsUserStruct *)->value_tags)

#define VALID_VT_TYPE_REF(ref) (SvROK(ref) && SvTYPE(SvRV(ref)) <= SVt_PVMG)
#define VALID_AV_TAGS(sv) (SvOK(sv) && SvTYPE(sv) == SVt_PVAV)
#define VALID_HV_TAGS(sv) (SvOK(sv) && SvTYPE(sv) == SVt_PVHV)

/*** UTILTIIES ***/

void av_append_uniq(pTHX_ SV *sav, SV *tag)
{
    assert(VALID_AV_TAGS(sav));
    assert(SvROK(tag));

    AV *av = (AV *)sav;

    SV **svp = AvARRAY(av);
    Size_t count = av_count(av);
    for(U32 idx = 0; idx < count; idx++) {
        // Skip duplicates
        if(SvROK(svp[idx]) && SvRV(tag) == SvRV(svp[idx])) {
            return;
        }
    }

    SV *ret = newSVsv(tag);
    av_push_simple(av, ret);

    return;
}

void av_append(pTHX_ SV *sav, SV *tag)
{
    assert(VALID_AV_TAGS(sav));
    assert(tag);

    SV *new_tag = newSVsv(tag);
    av_push_simple((AV *)sav, new_tag);
    return;
}

void hv_inc_count(pTHX_ SV *shv, SV *tag)
{
    // FIXME - figure out why DISARM_INFECT is needed here:
    //  (without it, hv_store_ent causes a recursive call to infect_value_tags,
    //  apparently on the temporary SV used to store the sum of the two vars)
    /*
     *
TEST: combine var_two and var_one
NCM DEBUG: >infect_value_tags: osv: 0xda800360, nsv: 0xda9224b8
NCM DEBUG: <infect_value_tags: dup_tags
NCM DEBUG: >infect_value_tags: osv: 0xda9224b8, nsv: 0xda894100
NCM DEBUG: <infect_value_tags: dup_tags
NCM DEBUG: >infect_value_tags: osv: 0xda894100, nsv: 0xda9224b8
NCM DEBUG:   iter_begin
NCM DEBUG:     =iter_begin_hash
NCM DEBUG:     iter_next: 0
NCM DEBUG:     >iter_next_hash
NCM DEBUG:     he: 0xd9e63d80
NCM DEBUG:     add_tag: 0xda6f2fa8
NCM DEBUG:     >hv_inc_count: shv: 0xd9e5e3d0
NCM DEBUG:       hv_fetch_ent
NCM DEBUG:       hv_store_ent (no he)
NCM DEBUG: >infect_value_tags: osv: 0xda9224b8, nsv: 0xd9e6c348
NCM DEBUG: <infect_value_tags: dup_tags
NCM DEBUG:       hv_store_ent RETURN
NCM DEBUG:     <hv_inc_count:
NCM DEBUG:     iter_next: 1
NCM DEBUG:     >iter_next_hash
NCM DEBUG:     he: 0x0
NCM DEBUG:     <iter_next_hash: NULL
NCM DEBUG: <infect_value_tags
NCM DEBUG: >infect_value_tags: osv: 0xda894100, nsv: 0xda88a958
NCM DEBUG: <infect_value_tags: dup_tags

     */
    /*
TEST: combine var_one and var_two
NCM DEBUG: >infect_value_tags: osv: 0xda894190, nsv: 0xda9224b8
NCM DEBUG: <infect_value_tags: dup_tags
NCM DEBUG: >infect_value_tags: osv: 0xda8942e0, nsv: 0xda9224b8
NCM DEBUG:   iter_begin
NCM DEBUG:     =iter_begin_hash
NCM DEBUG:     iter_next: 0
NCM DEBUG:     >iter_next_hash
NCM DEBUG:     he: 0xda6e1e80
NCM DEBUG:     add_tag: 0xda832c90
NCM DEBUG:     >hv_inc_count: shv: 0xd9e5e3d0
NCM DEBUG:       hv_fetch_ent
NCM DEBUG:       hv_store_ent (no he)
NCM DEBUG: >infect_value_tags: osv: 0xda9224b8, nsv: 0xda8e0480
NCM DEBUG: <infect_value_tags: dup_tags
NCM DEBUG:       hv_store_ent RETURN
NCM DEBUG:     <hv_inc_count:
NCM DEBUG:     iter_next: 1
NCM DEBUG:     >iter_next_hash
NCM DEBUG:     he: 0x0
NCM DEBUG:     <iter_next_hash: NULL
NCM DEBUG: <infect_value_tags
NCM DEBUG: >infect_value_tags: osv: 0xda9224b8, nsv: 0xda894448
NCM DEBUG: >infect_value_tags: osv: 0xda8e0480, nsv: 0xda9224b8
NCM DEBUG:   iter_begin
NCM DEBUG:     =iter_begin_hash
NCM DEBUG:     iter_next: 0
NCM DEBUG:     >iter_next_hash
NCM DEBUG:     he: 0xda88bcb8
NCM DEBUG:     add_tag: 0xda8e02b8
NCM DEBUG:     >hv_inc_count: shv: 0xd9e5e3d0
NCM DEBUG:       hv_fetch_ent
NCM DEBUG:          he: 0xda88c5a0
NCM DEBUG: >infect_value_tags: osv: 0xda8e0480, nsv: 0xda9224b8
NCM DEBUG:   iter_begin
NCM DEBUG:     =iter_begin_hash
NCM DEBUG:     iter_next: 0
NCM DEBUG:     >iter_next_hash
NCM DEBUG:     he: 0xda88bcb8
NCM DEBUG:     add_tag: 0xda8e02b8
NCM DEBUG:     >hv_inc_count: shv: 0xd9e5e3d0
NCM DEBUG:       hv_fetch_ent
NCM DEBUG:          he: 0xda88c5a0
NCM DEBUG: >infect_value_tags: osv: 0xda8e0480, nsv: 0xda9224b8
NCM DEBUG:   iter_begin
NCM DEBUG:     =iter_begin_hash
NCM DEBUG:     iter_next: 0
NCM DEBUG:     >iter_next_hash
NCM DEBUG:     he: 0xda88bcb8
NCM DEBUG:     add_tag: 0xda8e02b8
NCM DEBUG:     >hv_inc_count: shv: 0xd9e5e3d0
NCM DEBUG:       hv_fetch_ent
NCM DEBUG:          he: 0xda88c5a0
NCM DEBUG: >infect_value_tags: osv: 0xda8e0480, nsv: 0xda9224b8
NCM DEBUG:   iter_begin
NCM DEBUG:     =iter_begin_hash
NCM DEBUG:     iter_next: 0
NCM DEBUG:     >iter_next_hash
NCM DEBUG:     he: 0xda88bcb8
NCM DEBUG:     add_tag: 0xda8e02b8
NCM DEBUG:     >hv_inc_count: shv: 0xd9e5e3d0
NCM DEBUG:       hv_fetch_ent
NCM DEBUG:          he: 0xda88c5a0

     */
    ENTER_DISARM_INFECT;
fprintf(stderr, "NCM DEBUG:     >hv_inc_count: shv: 0x%x\n", shv);
    assert(VALID_HV_TAGS(shv));
    assert(tag);

    HV *hv = (HV *)shv;

fprintf(stderr, "NCM DEBUG:       hv_fetch_ent\n");
    HE *he = hv_fetch_ent(hv, tag, FALSE, 0);
    if (he) {
fprintf(stderr, "NCM DEBUG:          he: 0x%x\n", he);
        SV *val = HeVAL(he);
fprintf(stderr, "NCM DEBUG:          val: %d\n", SvIV(val));
fprintf(stderr, "NCM DEBUG:          SvIV_set: %d\n", SvIV(val) + 1);
        SvIV_set(val, SvIV(val) + 1);
    }
    else {
fprintf(stderr, "NCM DEBUG:       hv_store_ent (no he)\n");
        hv_store_ent(hv, tag, newSViv(1), 0);
fprintf(stderr, "NCM DEBUG:       hv_store_ent RETURN\n");
    }

fprintf(stderr, "NCM DEBUG:     <hv_inc_count:\n");
    LEAVE_DISARM_INFECT;
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
    return (SV *)newAV();
}

static SV *make_hash_value_tags(pTHX)
{
    return (SV *)newHV();
}

static SV *dup_array_value_tags(pTHX_ SV *value_tags)
{
    return (SV *)newAVav((AV *)value_tags);
}

static SV *dup_hash_value_tags(pTHX_ SV *value_tags)
{
    return (SV *)newHVhv((HV *)value_tags);
}

static void free_value_tags(pTHX_ SV *sv, MAGIC *mg)
{
    assert(sv);
    assert(mg);     // Just In Case
    SV *vt = VALUETAGS(mg);
    if (vt) {
        SvREFCNT_dec(vt);
        VALUETAGS(mg) = NULL;
    }
}

static SV *make_array_retval(pTHX_ MAGIC *mg)
{
    assert(mg);
    SV *vt = VALUETAGS(mg);
    assert(SvOK(vt) && SvTYPE(vt) == SVt_PVAV);

    AV *results = newAVav((AV *)vt);

    return newRV((SV *)results);
}

static SV *make_hash_retval(pTHX_ MAGIC *mg)
{
    assert(mg);

    SV *vt = VALUETAGS(mg);
    assert(SvOK(vt) && SvTYPE(vt) == SVt_PVHV);
    HV *results = newHVhv((HV *)vt);

    return newRV((SV *)results);
}

void infect_value_tags(pTHX_ SV *osv, MAGIC *omg, SV *nsv, MAGIC *nmg)
{
    assert(osv);
    assert(omg);
    assert(nsv);
fprintf(stderr, "NCM DEBUG: >infect_value_tags: osv: 0x%x, nsv: 0x%x\n", osv, nsv);

    SV *vt_type = MgAUXSV(omg);
    struct ValueTagsSpec *vt_spec = get_vt_spec(vt_type);

    SV *ovt = VALUETAGS(omg);
    if (!ovt) {
fprintf(stderr, "NCM DEBUG: <infect_value_tags: no tags\n");
        return;
    }

    // nmg is never set, since MGv2f_SCALARVALUE_INFECTIOUS is not set
    nmg = get_value_tags_magic(vt_type, nsv);

    if (!nmg) {
        SV *nvt = vt_spec->behavior->dup_tags(aTHX_ ovt);
        nmg = add_value_tags_magic(vt_type, nsv, nvt);
fprintf(stderr, "NCM DEBUG: <infect_value_tags: dup_tags\n");
        return;
    }

    void *iter_cxt;
fprintf(stderr, "NCM DEBUG:   iter_begin\n");
    vt_spec->behavior->iter_begin(aTHX_ ovt, &iter_cxt);
    SV *tag;
    int foo = 0;
fprintf(stderr, "NCM DEBUG:     iter_next: %d\n", foo++);
    while ((tag = vt_spec->behavior->iter_next(aTHX_ ovt, &iter_cxt))) {
fprintf(stderr, "NCM DEBUG:     add_tag: 0x%x\n", tag);
        vt_spec->behavior->add_tag(aTHX_ VALUETAGS(nmg), tag);
fprintf(stderr, "NCM DEBUG:     iter_next: %d\n", foo++);
    }
    if (vt_spec->behavior->iter_end) {
        vt_spec->behavior->iter_end(aTHX_ ovt, &iter_cxt);
    }

fprintf(stderr, "NCM DEBUG: <infect_value_tags\n");
#ifdef DEBUG_TRACE_ANNOTATIONS
        // FIXME: handle adding trace magic somewhere
        // copying existing annotation: sv will always have debug tracing
//      if(new) {
//          sv_magicext(new, (SV *)make_traceav_copy(svp[idx]), PERL_MAGIC_ext, &vtbl_hound_debugtrace, NULL, 0);
//      }
#endif

}

static void iter_begin_array (pTHX_ SV *value_tags, void **iter_cxt)
{
    assert(value_tags);
    assert(iter_cxt);
    *(intptr_t *)iter_cxt = 0;
}

static SV *iter_next_array (pTHX_ SV *value_tags, void **iter_cxt)
{
    assert(value_tags);
    assert(iter_cxt);
    AV *av = (AV *)value_tags;
    intptr_t *idxp = (intptr_t *)iter_cxt;
    if (*idxp >= av_count(av)) {
        return NULL;
    }
    SV **tag_ref = av_fetch(av, *idxp, 0);
    if (!tag_ref)
        croak("iter_next_array: av_fetch returned null");
    SV *tag = *tag_ref;
    (*idxp)++;
    return tag;
}

static void iter_begin_hash (pTHX_ SV *value_tags, void **iter_cxt)
{
    assert(value_tags);
    assert(iter_cxt);
fprintf(stderr, "NCM DEBUG:     =iter_begin_hash\n");
    (void) hv_iterinit((HV *)value_tags);
};

static SV *iter_next_hash (pTHX_ SV *value_tags, void **iter_cxt)
{
    assert(value_tags);
    assert(iter_cxt);

fprintf(stderr, "NCM DEBUG:     >iter_next_hash\n");
    HE *he = hv_iternext((HV *)value_tags);

fprintf(stderr, "NCM DEBUG:     he: 0x%x\n", he);
    if (!he) {
fprintf(stderr, "NCM DEBUG:     <iter_next_hash: NULL\n");
        return NULL;
    }

    return HeVAL(he);
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
        .iter_end    = NULL,
    },
    [BEHAVIOR_APPEND_ARRAY] = {
        .make_tags   = &make_array_value_tags,
        .dup_tags    = &dup_array_value_tags,
        .free_tags   = &free_value_tags,
        .make_retval = &make_array_retval,
        .add_tag     = &av_append,
        .iter_begin  = &iter_begin_array,
        .iter_next   = &iter_next_array,
        .iter_end    = NULL,
    },
    [BEHAVIOR_HASH_COUNT] = {
        .make_tags   = &make_hash_value_tags,
        .dup_tags    = &dup_hash_value_tags,
        .free_tags   = &free_value_tags,
        .make_retval = &make_hash_retval,
        .add_tag     = &hv_inc_count,
        .iter_begin  = &iter_begin_hash,
        .iter_next   = &iter_next_hash,
        .iter_end    = NULL,
    },
};

/*** VALUE-TAGS SPECIFICATIONS ***/

#define MY_CXT_KEY "Scalar::ValueTags::_registry" XS_VERSION

typedef struct {
    struct ValueTagsSpec *vt_specs;
    struct ValueTagsSpec *final_vt_spec;
} my_cxt_t;

START_MY_CXT

// FIXME - must make these thread-safe (is MY_CXT the correct pattern?)

static struct ValueTagsSpec *S_get_vt_spec(pTHX_ SV *vt_type)
{
    dMY_CXT;
    assert(vt_type);
    for (struct ValueTagsSpec *cur = MY_CXT.vt_specs; cur; cur = cur->next) {
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
    dMY_CXT;
    assert(vt_type);
    assert(behavior_type);

    const struct ValueTagsBehavior *behavior = &behaviors[SvIV(behavior_type)];

    struct ValueTagsSpec *new_vt_spec;
    Newx(new_vt_spec, 1, struct ValueTagsSpec);
    *new_vt_spec = (struct ValueTagsSpec){
        .next     = NULL,
        .vt_type  = SvREFCNT_inc(vt_type),
        .behavior = behavior,
    };

    if (MY_CXT.vt_specs) {
        MY_CXT.final_vt_spec->next = new_vt_spec;
        MY_CXT.final_vt_spec = new_vt_spec;
    }
    else {
        MY_CXT.vt_specs      = new_vt_spec;
        MY_CXT.final_vt_spec = new_vt_spec;
    }
}

/*** MAGIC ***/

static MAGIC *S_get_value_tags_magic(pTHX_ SV *vt_type, SV *sv)
{
    assert(vt_type);
    assert(sv);

    MAGIC *mg = NULL;
    if (SvTYPE(sv) >=  SVt_PVMG) {
        mg = sv_magicv2_find_by_auxsv(sv, vt_type);
    }

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

    struct ValueTagsSpec *vt_spec = get_vt_spec(vt_type);

    // FIXME - detect and handle sv_magicv2_add failure?
    MAGIC *mg = sv_magicv2_add(sv, (struct MagicFunctions *)&magic_funcs, 0, vt_type);

    // MgAUXSV refcnt is automatically decremented on mg destroy, so inc here
    SvREFCNT_inc(vt_type);

    if (!value_tags) {
        value_tags = vt_spec->behavior->make_tags(aTHX);
    }

    VALUETAGS(mg) = value_tags;

    return mg;
}

static MAGIC *S_init_value_tags_magic(pTHX_ SV *vt_type, SV *sv, SV *value_tags)
{
    assert(vt_type);
    assert(sv);

    MAGIC *mg = get_value_tags_magic(vt_type, sv);

    if (!mg) {
        mg = add_value_tags_magic(vt_type, sv, value_tags);
    }

    return mg;
}

static MAGIC *S_remove_value_tags_magic(pTHX_ SV *vt_type, SV *sv)
{
    assert(vt_type);
    assert(sv);

    MAGIC *mg = get_value_tags_magic(vt_type, sv);

    if (mg) {
        sv_magicv2_remove(sv, mg);
    }

    // API FIXME - should remove_value_tags_magic return old magic???
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
    if (!SvIOK(behavior))
      croak("Expected an integer for behavior");    // FIXME: need better error
    IV idx = SvIV(behavior);
    if (idx < 0 || idx >= MAX_BEHAVIOR)
      croak("Unknown behavior"); // FIXME: need better error

    SV *vt_type = newSV(0);

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
    if (!VALID_VT_TYPE_REF(vt_type_ref))
        croak("Expected a SCALAR reference for vt_type");   // FIXME - need better validation
    if (!SvROK(sv_ref) || SvTYPE(SvRV(sv_ref)) > SVt_PVMG)
        croak("Expected a SCALAR reference for target variable");

    // FIXME: add tag validation to vt_spec, and validate tag here

    SV *vt_type = SvRV(vt_type_ref);
    struct ValueTagsSpec *vt_spec = get_vt_spec(vt_type);

    MAGIC *mg = init_value_tags_magic(vt_type, SvRV(sv_ref), NULL);

    vt_spec->behavior->add_tag(aTHX_ VALUETAGS(mg), tag);
#endif

SV *
get_value_tags (SV *vt_type_ref, SV *sv_ref)
  CODE:
#ifdef HAVE_VALUE_MAGIC
    if (!VALID_VT_TYPE_REF(vt_type_ref))
        croak("Expected a SCALAR reference for vt_type");   // FIXME - need better validation
    if (!SvROK(sv_ref) || SvTYPE(SvRV(sv_ref)) > SVt_PVMG)
        croak("Expected a SCALAR reference for target variable");

    SV *vt_type = SvRV(vt_type_ref);
    SV *sv = SvRV(sv_ref);

    MAGIC *mg = get_value_tags_magic(vt_type, sv);

    struct ValueTagsSpec *vt_spec = get_vt_spec(vt_type);

    if (mg) {
        RETVAL = vt_spec->behavior->make_retval(aTHX_ mg);
    }
    else {
        RETVAL = NULL;
    }
#else
    RETVAL = NULL;
#endif
  OUTPUT:
    RETVAL

void
clear_value_tags (SV *vt_type_ref, SV *sv_ref)
  CODE:
#ifdef HAVE_VALUE_MAGIC
    if (!VALID_VT_TYPE_REF(vt_type_ref))
        croak("Expected a SCALAR reference for vt_type");   // FIXME - need better validation
    if (!SvROK(sv_ref) || SvTYPE(SvRV(sv_ref)) > SVt_PVMG)
        croak("Expected a SCALAR reference for target variable");

    SV *vt_type = SvRV(vt_type_ref);
    SV *sv = SvRV(sv_ref);
    MAGIC *mg = get_value_tags_magic(vt_type, sv);

    if (mg) {
        remove_value_tags_magic(vt_type, sv);
    }
#endif

void
CLONE(...)
  CODE:
    MY_CXT_CLONE;

BOOT:
{
    MY_CXT_INIT;
    MY_CXT.vt_specs = NULL;
    MY_CXT.final_vt_spec = NULL;
}
