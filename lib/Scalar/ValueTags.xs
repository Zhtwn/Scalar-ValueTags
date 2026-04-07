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

#define VALUETAGS(mg) (MgUSERSTRUCT(mg, struct ValueTagsUserStruct *)->value_tags)

/*** UTILTIIES ***/

static SV *av_append_uniq(pTHX_ SV *sav, SV *tag)
{
    assert(sav);
    assert(tag);
    assert(SvPOK(sav));
    assert(SvTYPE(sav) == SVt_PVAV);
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
            return NULL;
        }
    }

    fprintf(stderr, "  append new tag\n");
    SV *ret = newSVsv(tag);
    av_push_simple(av, ret);

    fprintf(stderr, "<av_append_uniq\n");
    return ret;
}

static SV *av_append(pTHX_ SV *sav, SV *tag)
{
    assert(sav);
    assert(tag);

    SV *new_tag = newSVsv(tag);
    av_push_simple((AV *)sav, new_tag);
    return new_tag;
}

static SV *hv_inc_count(pTHX_ SV *shv, SV *tag)
{
    assert(shv);
    assert(tag);
    assert(SvPOK(shv));
    assert(SvTYPE(shv) == SVt_PVHV);

    HV *hv = (HV *)shv;

    IV count = 1;
    SV *ret;
    HE *entry = hv_fetch_ent(hv, tag, FALSE, 0);
    if (entry) {
        SV *val = hv_iterval(hv, entry);
        count += SvIV(val);
    }
    ret = newSViv(count);
    hv_store_ent(hv, tag, ret, 0);

    return ret;
}

/*** FORWARD DECLARATIONS FOR MAGIC HANDLING ***/
#define get_value_tags_magic(vt_type, sv)  S_get_value_tags_magic(aTHX_ vt_type, sv)
static MAGIC *S_get_value_tags_magic(pTHX_ SV *vt_type, SV *sv);

#define init_value_tags_magic(vt_type, sv)  S_init_value_tags_magic(aTHX_ vt_type, sv)
static MAGIC *S_init_value_tags_magic(pTHX_ SV *vt_type, SV *sv);

#define remove_value_tags_magic(vt_type, sv)  S_remove_value_tags_magic(aTHX_ vt_type, sv)
static MAGIC *S_remove_value_tags_magic(pTHX_ SV *vt_type, SV *sv);

/*** BEHAVIORS ***/

static SV *make_array_value_tags(pTHX)
{
    AV *av = newAV();
    return (SV *)av;
}

static void free_value_tags(pTHX_ SV *sv, MAGIC *mg)
{
    assert(mg);
    fprintf(stderr, ">free_array_value_tags\n");
    fprintf(stderr, "  VALUETAGS\n");
    SV *vt = VALUETAGS(mg);
    if (vt) {
        fprintf(stderr, "  SvREFCNT_DEC\n");
        SvREFCNT_dec(vt);
        VALUETAGS(mg) = NULL;
    }
    fprintf(stderr, "<free_array_value_tags\n");
}

static SV *make_hash_value_tags(pTHX_)
{
    HV *hv = newHV();
    return (SV *)hv;
}

static SV *make_array_retval(pTHX_ MAGIC *mg)
{
    assert(mg);
    fprintf(stderr, ">make_array_retval\n");
    fprintf(stderr, "  VALUETAGS\n");
    AV *av = (AV *)VALUETAGS(mg);

    U32 count = av_count(av);
    fprintf(stderr, "  count: %u\n", count);
    fprintf(stderr, "  results: newAVav\n");
    AV *results = newAVav(av);

    fprintf(stderr, "<make_array_retval\n");
    return (SV *)results;
}

static SV *make_hash_retval(pTHX_ MAGIC *mg)
{
    assert(mg);

    HV *results = newHVhv((HV *)VALUETAGS(mg));

    return (SV *)results;
}

void infect_uniq_ref_array(pTHX_ SV *osv, MAGIC *omg, SV *nsv, MAGIC *nmg)
{
//  ENTER_DISARM_INFECT;
    assert(osv);
    assert(omg);
    assert(nsv);

    fprintf(stderr, ">infect_uniq_ref_array\n");
    fprintf(stderr, "  osv: 0x%x\n", osv);
    fprintf(stderr, "  nsv: 0x%x\n", nsv);

    fprintf(stderr, "  omg count: %u\n", av_count((AV *)VALUETAGS(omg)));

    SV *vt_type = MgAUXSV(omg);

    // nmg is never set, since MGv2f_SCALARVALUE_INFECTIOUS is not set
    nmg = get_value_tags_magic(vt_type, nsv);

    if (!nmg) {
        fprintf(stderr, "  init_value_tags_magic\n");
        nmg = init_value_tags_magic(vt_type, nsv);
        fprintf(stderr, "  copying VALUETAGS\n");
        VALUETAGS(nmg) = (SV *)newAVav((AV *)VALUETAGS(omg));
        fprintf(stderr, "<infect_uniq_ref_array\n");
        return;
    }

    fprintf(stderr, "  VALUETAGS\n");
    AV *oav = (AV *)VALUETAGS(omg);
    assert(oav);
    U32 count = av_count(oav);
    if (!count)
        return;

    AV *nav = (AV *)VALUETAGS(nmg);

    SV **svp = AvARRAY(oav);
    for(U32 idx = 0; idx < count; idx++) {
        fprintf(stderr, "  idx %u: 0x%x\n", idx, svp[idx]);
        SV *new = av_append_uniq(aTHX_ (SV *)nav, svp[idx]);
#ifdef DEBUG_TRACE_ANNOTATIONS
        // FIXME: handle adding trace magic somewhere
        // copying existing annotation: sv will always have debug tracing
//      if(new) {
//          sv_magicext(new, (SV *)make_traceav_copy(svp[idx]), PERL_MAGIC_ext, &vtbl_hound_debugtrace, NULL, 0);
//      }
#endif
    }
//  LEAVE_DISARM_INFECT;
    fprintf(stderr, "<infect_uniq_ref_array\n");
}

void infect_append_array(pTHX_ SV *osv, MAGIC *omg, SV *nsv, MAGIC *nmg)
{
    assert(osv);
    assert(omg);
    assert(nsv);

    fprintf(stderr, ">infect_append_array\n");
    fprintf(stderr, "  osv: 0x%x\n", osv);
    fprintf(stderr, "  nsv: 0x%x\n", nsv);

    AV *oav = (AV *)VALUETAGS(omg);
    U32 count = av_count(oav);
    if (!count)
        return;

    SV *vt_type = MgAUXSV(omg);

    fprintf(stderr, "  omg count: %u\n", av_count((AV *)VALUETAGS(omg)));

    // nmg is never set, since MGv2f_SCALARVALUE_INFECTIOUS is not set
    nmg = get_value_tags_magic(vt_type, nsv);

    if (!nmg) {
        fprintf(stderr, "  init_value_tags_magic\n");
        nmg = init_value_tags_magic(MgAUXSV(omg), nsv);
        fprintf(stderr, "  copying VALUETAGS\n");
//      ENTER_DISARM_INFECT;
        VALUETAGS(nmg) = (SV *)newAVav((AV *)VALUETAGS(omg));
//      LEAVE_DISARM_INFECT;
        fprintf(stderr, "<infect_append_array\n");
        return;
    }

    AV *nav = (AV *)VALUETAGS(nmg);
    SV **svp = AvARRAY(oav);
    for(U32 idx = 0; idx < count; idx++) {
        fprintf(stderr, "  idx %u: 0x%x\n", idx, svp[idx]);
        SV *new = av_append(aTHX_ (SV *)nav, svp[idx]);
#ifdef DEBUG_TRACE_ANNOTATIONS
        // FIXME: handle adding trace magic somewhere
        // copying existing annotation: sv will always have debug tracing
//      if(new) {
//          sv_magicext(new, (SV *)make_traceav_copy(svp[idx]), PERL_MAGIC_ext, &vtbl_hound_debugtrace, NULL, 0);
//      }
#endif
  }
}

void infect_hash_count(pTHX_ SV *osv, MAGIC *omg, SV *nsv, MAGIC *nmg)
{
    assert(osv);
    assert(omg);
    assert(nsv);

    HV *ohv = (HV *)VALUETAGS(omg);
    assert(ohv);

    if (!hv_iterinit(ohv))
        return;

    // vt_type is stored in AUXSV
    if (!nmg)
        nmg = init_value_tags_magic(nsv, MgAUXSV(omg));

    HV *nhv = (HV *)VALUETAGS(nmg);

    assert(nhv);

    HE *oentry;
    while (oentry = hv_iternext(ohv)) {
        SV *oval = hv_iterval(ohv, oentry);
        SV *key = HeSVKEY(oentry);
        IV ncount = SvIV(oval);
        HE *nentry = hv_fetch_ent(nhv, key, FALSE, 0);
        if (nentry) {
            SV *nval = hv_iterval(nhv, nentry);
            ncount += SvIV(nval);
        }
        hv_store_ent(nhv, key, newSViv(ncount), 0);

#ifdef DEBUG_TRACE_ANNOTATIONS
        // FIXME: handle adding trace magic somewhere
        // copying existing annotation: sv will always have debug tracing
//      if(new) {
//          sv_magicext(new, (SV *)make_traceav_copy(svp[idx]), PERL_MAGIC_ext, &vtbl_hound_debugtrace, NULL, 0);
//      }
#endif
    }
}

struct ValueTagsBehaviorVtbl {
    SV*  (*make_value_tags)(pTHX_);
    void (*free_value_tags)(pTHX_ SV *sv, MAGIC *mg);
    SV*  (*add_tag)(pTHX_ SV *sv, SV *tag);
    SV*  (*make_retval)(pTHX_ MAGIC *mg);
    void (*infect_magic)(pTHX_ SV *osv, MAGIC *omg, SV *nsv, MAGIC *nmg);
};

enum behavior_types {
    BEHAVIOR_UNIQUE_REF_ARRAY,
    BEHAVIOR_APPEND_ARRAY,
    BEHAVIOR_HASH_COUNT,
    MAX_BEHAVIOR
};

static const struct ValueTagsBehaviorVtbl behavior_vtbls[] = {
    [BEHAVIOR_UNIQUE_REF_ARRAY] = {
        .make_value_tags = make_array_value_tags,
        .free_value_tags = free_value_tags,
        .make_retval     = make_array_retval,
        .add_tag         = av_append_uniq,
        .infect_magic    = infect_uniq_ref_array,
    },
    [BEHAVIOR_APPEND_ARRAY] = {
        .make_value_tags = make_array_value_tags,
        .free_value_tags = free_value_tags,
        .make_retval     = make_array_retval,
        .add_tag         = av_append,
        .infect_magic    = infect_append_array,
    },
    [BEHAVIOR_HASH_COUNT] = {
        .make_value_tags = make_hash_value_tags,
        .free_value_tags = free_value_tags,
        .make_retval     = make_hash_retval,
        .add_tag         = hv_inc_count,
        .infect_magic    = infect_hash_count,
    },
};

/*** VALUE-TAGS SPECIFICATIONS ***/

struct ValueTagsSpec {
    struct ValueTagsSpec                   *next;
    SV                                     *vt_type;
    SV                                     *(*make_value_tags)();
    SV                                     *(*make_retval)(pTHX_ MAGIC *mg);
    SV                                     *(*add_tag)(pTHX_ SV *sv, SV *tag);
    const struct ScalarValueMagicFunctions *magic_funcs;
};

static struct ValueTagsSpec *vt_specs = NULL;
static struct ValueTagsSpec *final_vt_spec = NULL;

#define get_vt_spec(vt_type) S_get_vt_spec(aTHX_ vt_type)
static struct ValueTagsSpec *S_get_vt_spec(pTHX_ SV *vt_type)
{
    fprintf(stderr, ">S_get_vt_spec\n");
    fprintf(stderr, "  vt_type: 0x%x\n", vt_type);
    for (struct ValueTagsSpec *cur = vt_specs; cur; cur = cur->next) {
        fprintf(stderr, "  next cur\n");
        if (cur && (cur->vt_type == vt_type)) {
            fprintf(stderr, "<S_get_vt_spec: return found\n");
            return cur;
        }
    }
    fprintf(stderr, "<S_get_vt_spec: return NOT found\n");
//  croak("vt_type not registered");
    return NULL;
}

#define set_vt_type_behavior(vt_type, behavior_idx) S_set_vt_type_behavior(aTHX_ vt_type, behavior_idx)
static void S_set_vt_type_behavior(pTHX_ SV *vt_type, SV *behavior)
{
    // FIXME - validate parameters
    struct ValueTagsBehaviorVtbl behavior_vtbl = behavior_vtbls[(int)SvIV(behavior)];

    fprintf(stderr, ">S_set_vt_type_behavor\n");
    struct ScalarValueMagicFunctions *magic_funcs;
    Newx(magic_funcs, 1, struct ScalarValueMagicFunctions);
    *magic_funcs = (struct ScalarValueMagicFunctions){
        .ver       = 2, /* Magic v2 */
        .shape     = MGv2s_SCALARVALUE,
        .free_mg   = behavior_vtbl.free_value_tags,
        .infect    = behavior_vtbl.infect_magic,
        .user_size = sizeof(struct ValueTagsUserStruct),

        /* FIXME: NEEDED?
        .clone = ...,
        */
    };
    struct ValueTagsSpec *new_vt_spec;
    Newx(new_vt_spec, 1, struct ValueTagsSpec);
    *new_vt_spec = (struct ValueTagsSpec){
        .next            = NULL,
        .vt_type         = SvREFCNT_inc(vt_type),
        .make_value_tags = behavior_vtbl.make_value_tags,
        .make_retval     = behavior_vtbl.make_retval,
        .add_tag         = behavior_vtbl.add_tag,
        .magic_funcs     = magic_funcs,
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
    assert(sv);
    assert(vt_type);
    fprintf(stderr, ">S_get_value_tags_magic\n");

    MAGIC *mg = NULL;
    if (SvTYPE(sv) >=  SVt_PVMG) {
    fprintf(stderr, "  find magic\n");
        mg = sv_magicv2_find_by_auxsv(sv, vt_type);
        if (mg) fprintf(stderr, "  found magic\n"); else fprintf(stderr, "  no magic found\n");
    }

    if (mg) fprintf(stderr, "<S_get_value_tags_magic: return magic\n"); else fprintf(stderr, "<S_get_value_tags_magic: NO magic\n");
    return mg;
}

static MAGIC *S_init_value_tags_magic(pTHX_ SV *vt_type, SV *sv)
{
    assert(sv);
    assert(vt_type);
    fprintf(stderr, "<S_init_value_tags_magic\n");

    fprintf(stderr, "  get_value_tags_magic\n");
    MAGIC *mg = get_value_tags_magic(vt_type, sv);
    if (mg) fprintf(stderr, "  found magic\n");
    if (!mg) {
        fprintf(stderr, "  get_vt_spec\n");
        struct ValueTagsSpec *vt_spec = get_vt_spec(vt_type);
        fprintf(stderr, "  get magic_funcs\n");

        // FIXME - detect and handle sv_magicv2_add failure?
        fprintf(stderr, "  sv_magicv2_add\n");
        mg = sv_magicv2_add(sv, (struct MagicFunctions *)vt_spec->magic_funcs, 0, vt_type);

        // SvAUX refcnt is automatically decremented on mg destroy, so inc here
        SvREFCNT_inc(vt_type);

        fprintf(stderr, "  make_value_tags\n");
        SV *value_tags = vt_spec->make_value_tags(aTHX_);
        fprintf(stderr, "  set VALUETAGS\n");
        VALUETAGS(mg) = value_tags;
    }

    fprintf(stderr, "<S_init_value_tags_magic: return magic\n");
    return mg;
}

static MAGIC *S_remove_value_tags_magic(pTHX_ SV *vt_type, SV *sv)
{
    assert(sv);
    assert(vt_type);
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
    if (!SvIOK(behavior))
      croak("Expected an integer for behavior");    // FIXME: need better error
    IV idx = SvIV(behavior);
    if (idx >= MAX_BEHAVIOR)
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
    if (!SvROK(sv_ref) || SvTYPE(SvRV(sv_ref)) > SVt_PVMG)
        croak("Expected a SCALAR reference for target variable");
    fprintf(stderr, ">add_value_tag\n");

    // FIXME: add tag validation to vt_spec, and validate tag here

    fprintf(stderr, "  sv: 0x%x\n", SvRV(sv_ref));
    SV *vt_type = SvRV(vt_type_ref);
    fprintf(stderr, "init_value_tags_magic\n");
    fprintf(stderr, "  vt_type_ref: 0x%x\n", vt_type_ref);
    fprintf(stderr, "  vt_type: 0x%x\n", vt_type);
    MAGIC *mg = init_value_tags_magic(vt_type, SvRV(sv_ref));
    if (mg) { fprintf(stderr, "  got mg\n"); } else { fprintf(stderr, "  NO mg\n"); }

    fprintf(stderr, "  get_vt_spec\n");
    struct ValueTagsSpec *vt_spec = get_vt_spec(vt_type);

    fprintf(stderr, "  vt_spec->add_tag\n");
    vt_spec->add_tag(aTHX_ VALUETAGS(mg), tag);

    fprintf(stderr, "<add_value_tag\n");
#endif

SV *
get_value_tags (SV *vt_type_ref, SV *sv_ref)
  CODE:
#ifdef HAVE_VALUE_MAGIC
    if (!SvROK(sv_ref) || SvTYPE(SvRV(sv_ref)) > SVt_PVMG)
        croak("Expected a SCALAR reference for target variable");

    fprintf(stderr, ">get_value_tags\n");
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
        RETVAL = newRV(vt_spec->make_retval(aTHX_ mg));
//      RETVAL = vt_spec->make_retval(aTHX_ mg);
    }
    else {
        fprintf(stderr, "  NO magic\n");
        fprintf(stderr, "<get_value_tags: undef\n");
        RETVAL = NULL;
    }
#else
    fprintf(stderr, "  ValueTags not enabled\n");
    fprintf(stderr, "<get_value_tags: undef\n");
    RETVAL = NULL;
#endif
  OUTPUT:
    RETVAL

void
clear_value_tags (SV *vt_type_ref, SV *sv_ref)
  CODE:
#ifdef HAVE_VALUE_MAGIC
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

