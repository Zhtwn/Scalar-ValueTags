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

#define MgVALUETAGS(mg) (MgUSERSTRUCT(mg, struct ValueTagsUserStruct *)->value_tags)

struct ValueTagsUserStruct {
    SV *value_tags;
};

/*** UTILTIIES ***/

static SV *av_append_uniq(pTHX_ SV *sav, SV *tag)
{
    assert(sav);
    assert(tag);
    assert(SvTYPE(sav) == SVt_PVAV);
    AV *av = (AV *)sav;

    SV **svp = AvARRAY(av);
    for(U32 idx = 0; idx < av_count(av); idx++) {
        // Skip duplicates
        if(SvROK(tag) && SvROK(svp[idx]) && SvRV(tag) == SvRV(svp[idx])) {
            return NULL;
        }
    }

    SV *ret = newSVsv(tag);
    av_push_simple(av, ret);

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

static SV *make_array_value_tags(pTHX_)
{
    AV *av = newAV();
    return (SV *)av;
}

// FIXME - is this needed?
static void free_array_value_tags(pTHX_ SV *sv, MAGIC *mg)
{
    assert(mg);
    AV *av = (AV *)MgVALUETAGS(mg);
    if (av) {
        av_clear(av);
    }
}

static SV *make_hash_value_tags(pTHX_)
{
    HV *hv = newHV();
    return (SV *)hv;
}

// FIXME - is this needed?
static void free_hash_value_tags(pTHX_ SV *sv, MAGIC *mg)
{
    assert(mg);
    HV *hv = (HV *)MgVALUETAGS(mg);
    if (hv)
        hv_clear(hv);
}

static SV *make_array_retval(pTHX_ MAGIC *mg)
{
    assert(mg);
    AV *av = (AV *)MgVALUETAGS(mg);

    AV *results = newAVav(av);

    return (SV *)results;
}

static SV *make_hash_retval(pTHX_ MAGIC *mg)
{
    assert(mg);

    HV *results = newHVhv((HV *)MgVALUETAGS(mg));

    return (SV *)results;
}

void infect_uniq_ref_array(pTHX_ SV *osv, MAGIC *omg, SV *nsv, MAGIC *nmg)
{
//  ENTER_DISARM_INFECT;
    assert(osv);
    assert(omg);
    assert(nsv);

    SV *vt_type = MgAUXSV(omg);

    // nmg is never set, since MGv2f_SCALARVALUE_INFECTIOUS is not set
    nmg = get_value_tags_magic(vt_type, nsv);

    if (!nmg) {
        nmg = init_value_tags_magic(vt_type, nsv);
        SV *old_tags = MgVALUETAGS(nmg);
        MgVALUETAGS(nmg) = (SV *)newAVav((AV *)MgVALUETAGS(omg));
        SvREFCNT_dec(old_tags);
        return;
    }

    AV *oav = (AV *)MgVALUETAGS(omg);
    assert(oav);
    U32 count = av_count(oav);
    if (!count)
        return;

    AV *nav = (AV *)MgVALUETAGS(nmg);

    SV **svp = AvARRAY(oav);
    for(U32 idx = 0; idx < count; idx++) {
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
}

void infect_append_array(pTHX_ SV *osv, MAGIC *omg, SV *nsv, MAGIC *nmg)
{
    assert(osv);
    assert(omg);
    assert(nsv);

    AV *oav = (AV *)MgVALUETAGS(omg);
    U32 count = av_count(oav);
    if (!count)
        return;

    SV *vt_type = MgAUXSV(omg);

    // nmg is never set, since MGv2f_SCALARVALUE_INFECTIOUS is not set
    nmg = get_value_tags_magic(vt_type, nsv);

    if (!nmg) {
        nmg = init_value_tags_magic(vt_type, nsv);
//      ENTER_DISARM_INFECT;
        SV *old_tags = MgVALUETAGS(nmg);
        MgVALUETAGS(nmg) = (SV *)newAVav((AV *)MgVALUETAGS(omg));
        SvREFCNT_dec(old_tags);
//      LEAVE_DISARM_INFECT;
        return;
    }

    AV *nav = (AV *)MgVALUETAGS(nmg);
    SV **svp = AvARRAY(oav);
    for(U32 idx = 0; idx < count; idx++) {
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

    HV *ohv = (HV *)MgVALUETAGS(omg);
    assert(ohv);

    if (!hv_iterinit(ohv))
        return;

    // vt_type is stored in AUXSV
    if (!nmg)
        nmg = init_value_tags_magic(MgAUXSV(omg), nsv);

    HV *nhv = (HV *)MgVALUETAGS(nmg);

    assert(nhv);

    HE *oentry;
    while (oentry = hv_iternext(ohv)) {
        SV *oval = hv_iterval(ohv, oentry);
        SV *key = HeSVKEY_force(oentry);
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

#define BEHAVIOR_UNIQUE_REF_ARRAY 0
#define BEHAVIOR_APPEND_ARRAY     1
#define BEHAVIOR_HASH_COUNT       2
#define MAX_BEHAVIOR              3

static const struct ValueTagsBehaviorVtbl behavior_vtbls[] = {
    {
        .make_value_tags = make_array_value_tags,
        .free_value_tags = free_array_value_tags,
        .make_retval     = make_array_retval,
        .add_tag         = av_append_uniq,
        .infect_magic    = infect_uniq_ref_array,
    },
    {
        .make_value_tags = make_array_value_tags,
        .free_value_tags = free_array_value_tags,
        .make_retval     = make_array_retval,
        .add_tag         = av_append,
        .infect_magic    = infect_append_array,
    },
    {
        .make_value_tags = make_hash_value_tags,
        .free_value_tags = free_hash_value_tags,
        .make_retval     = make_hash_retval,
        .add_tag         = hv_inc_count,
        .infect_magic    = infect_hash_count,
    },
};
static const int behavior_count = sizeof(behavior_vtbls) / sizeof(behavior_vtbls[0]);

/*** VALUE-TAGS SPECIFICATIONS ***/

struct ValueTagsSpec {
    struct ValueTagsSpec             *next;
    SV                               *vt_type;
    SV                               *(*make_value_tags)();
    SV                               *(*make_retval)(pTHX_ MAGIC *mg);
    SV                               *(*add_tag)(pTHX_ SV *sv, SV *tag);
    struct ScalarValueMagicFunctions magic_funcs;
};

static struct ValueTagsSpec *vt_specs = NULL;
static struct ValueTagsSpec *final_vt_spec = NULL;

#define get_vt_spec(vt_type) S_get_vt_spec(aTHX_ vt_type)
static struct ValueTagsSpec *S_get_vt_spec(pTHX_ SV *vt_type)
{
    struct ValueTagsSpec *cur;
    for (cur = vt_specs; cur; cur = cur->next) {
        if (cur && (cur->vt_type == vt_type)) {
            return cur;
        }
    }
//  croak("vt_type not registered");
    return NULL;
}

#define set_vt_type_behavior(vt_type, behavior_idx) S_set_vt_type_behavior(aTHX_ vt_type, behavior_idx)
static void S_set_vt_type_behavior(pTHX_ SV *vt_type, SV *behavior)
{
    // FIXME - validate parameters
    struct ValueTagsBehaviorVtbl behavior_vtbl = behavior_vtbls[(int)SvIV(behavior)];

    SvREFCNT_inc(vt_type);
    struct ValueTagsSpec *new_vt_spec;
    Newx(new_vt_spec, 1, struct ValueTagsSpec);
    *new_vt_spec = (struct ValueTagsSpec){
        .next            = NULL,
        .vt_type         = vt_type,
        .make_value_tags = behavior_vtbl.make_value_tags,
        .make_retval     = behavior_vtbl.make_retval,
        .add_tag         = behavior_vtbl.add_tag,
        .magic_funcs     = (struct ScalarValueMagicFunctions) {
            .ver       = 2, /* Magic v2 */
            .shape     = MGv2s_SCALARVALUE,
            .free_mg   = behavior_vtbl.free_value_tags,
            .infect    = behavior_vtbl.infect_magic,
            .user_size = sizeof(struct ValueTagsUserStruct),

            /* FIXME: NEEDED?
            .clone = ...,
            */
        }
    };

    if (vt_specs) {
        final_vt_spec->next = new_vt_spec;
        final_vt_spec = new_vt_spec;
    }
    else {
        vt_specs      = new_vt_spec;
        final_vt_spec = new_vt_spec;
    }
}

/*** MAGIC ***/

static MAGIC *S_get_value_tags_magic(pTHX_ SV *vt_type, SV *sv)
{
    assert(sv);
    assert(vt_type);

    MAGIC *mg = NULL;
    if (SvTYPE(sv) >=  SVt_PVMG) {
        mg = sv_magicv2_find_by_auxsv(sv, vt_type);
    }

    return mg;
}

static MAGIC *S_init_value_tags_magic(pTHX_ SV *vt_type, SV *sv)
{
    assert(sv);
    assert(vt_type);

    MAGIC *mg = get_value_tags_magic(vt_type, sv);
    if (!mg) {
        struct ValueTagsSpec *vt_spec = get_vt_spec(vt_type);
        struct ScalarValueMagicFunctions *magic_funcs = &(vt_spec->magic_funcs);

        // FIXME - detect and handle sv_magicv2_add failure?
        mg = sv_magicv2_add(sv, (struct MagicFunctions *)magic_funcs, 0, vt_type);

        // SvAUX refcnt is automatically decremented on mg destroy, so inc here
        SvREFCNT_inc(vt_type);

        SV *value_tags = vt_spec->make_value_tags(aTHX_);
        MgVALUETAGS(mg) = value_tags;
    }

    return mg;
}

static MAGIC *S_remove_value_tags_magic(pTHX_ SV *vt_type, SV *sv)
{
    assert(sv);
    assert(vt_type);

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
    if (!SvROK(sv_ref) || SvTYPE(SvRV(sv_ref)) > SVt_PVMG)
        croak("Expected a SCALAR reference for target variable");

    // FIXME: add tag validation to vt_spec, and validate tag here

    SV *vt_type = SvRV(vt_type_ref);
    MAGIC *mg = init_value_tags_magic(vt_type, SvRV(sv_ref));

    struct ValueTagsSpec *vt_spec = get_vt_spec(vt_type);

    vt_spec->add_tag(aTHX_ MgVALUETAGS(mg), tag);
#endif

SV *
get_value_tags (SV *vt_type_ref, SV *sv_ref)
  CODE:
#ifdef HAVE_VALUE_MAGIC
    if (!SvROK(sv_ref) || SvTYPE(SvRV(sv_ref)) > SVt_PVMG)
        croak("Expected a SCALAR reference for target variable");

    SV *vt_type = SvRV(vt_type_ref);
    SV *sv = SvRV(sv_ref);

    MAGIC *mg = get_value_tags_magic(vt_type, sv);

    struct ValueTagsSpec *vt_spec = get_vt_spec(vt_type);

    if (mg) {
        RETVAL = newRV(vt_spec->make_retval(aTHX_ mg));
//      RETVAL = vt_spec->make_retval(aTHX_ mg);
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
    if (!SvROK(sv_ref) || SvTYPE(SvRV(sv_ref)) > SVt_PVMG)
        croak("Expected a SCALAR reference for target variable");

    SV *vt_type = SvRV(vt_type_ref);
    SV *sv = SvRV(sv_ref);
    MAGIC *mg = get_value_tags_magic(vt_type, sv);

    if (mg) {
        remove_value_tags_magic(vt_type, sv);
    }
#endif

