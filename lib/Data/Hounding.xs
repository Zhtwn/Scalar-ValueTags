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

/* Determine core hounding implementation, if any */
#if defined(sv_hook_add)
#  define HAVE_MAGIC_V2
#elif defined(sv_usertaint_applyto)
#  define HAVE_USERTAINT
#endif

#if defined(HAVE_MAGIC_V2) || defined(HAVE_USERTAINT)
#  define HAVE_HOUNDING
#endif

#ifdef HAVE_MAGIC_V2
#  define ENTER_DISARM_INFECT \
  ENTER;  \
  SAVESPTR(PL_viralmagic_annotations); PL_viralmagic_annotations = NULL
#endif

#ifdef HAVE_USERTAINT
#  define ENTER_DISARM_INFECT \
  ENTER;  \
  SAVESPTR(PL_usertaint_annotations); PL_usertaint_annotations = NULL
#endif

#define LEAVE_DISARM_INFECT  \
  LEAVE

/* Common low-level functions for both implementations */
#ifdef HAVE_HOUNDING

#define av_push_dup_if_uniq(av, sv)  S_av_push_dup_if_uniq(aTHX_ av, sv)
static SV *S_av_push_dup_if_uniq(pTHX_ AV *av, SV *sv)
{
  if(SvROK(sv)) {
    // Skip duplicates
    U32 idx;
    SV **svp = AvARRAY(av);
    for(idx = 0; idx < av_count(av); idx++)
      if(SvROK(svp[idx]) && SvRV(sv) == SvRV(svp[idx]))
        return NULL;
  }

  SV *ret = newSVsv(sv);
  av_push_simple(av, ret);
  return ret;
}

/* Declarations for required per-implementation low-level functions */
#define get_hounding_magic(sv)  S_get_hounding_magic(aTHX_ sv)
static MAGIC *S_get_hounding_magic(pTHX_ SV *sv);

#define add_hounding_magic(sv, av)  S_add_hounding_magic(aTHX_ sv, av)
static MAGIC *S_add_hounding_magic(pTHX_ SV *sv, AV *av);

#define remove_hounding_magic(sv)  S_remove_hounding_magic(aTHX_ sv)
static void S_remove_hounding_magic(pTHX_ SV *sv);

#define get_hounding_av(mg)  S_get_hounding_av(aTHX_ mg)
static AV *S_get_hounding_av(pTHX_ MAGIC *mg);

/* DEBUG_TRACE logic */
#ifdef DEBUG_TRACE_ANNOTATIONS

static MGVTBL vtbl_hound_debugtrace = { /* empty */ };

#define make_traceav_orig()  S_make_traceav_orig(aTHX)
static SV *S_make_traceav_orig(pTHX)
{
  ENTER_DISARM_INFECT;

  AV *trace = newAV();
  av_push(trace, newSVuv(0));
  av_push(trace, newSVpvf("%s:%d", CopFILE(PL_curcop), CopLINE(PL_curcop)));
  for(I32 cxix = cxstack_ix; cxix >= 0; cxix--) {
    if(av_count(trace) > 5)
      break;

    PERL_CONTEXT *cx = cxstack + cxix;
    if(CxTYPE(cx) == CXt_SUB) {
      COP *oldcop = cx->blk_oldcop;
      av_push(trace, newSVpvf("%s:%d", CopFILE(oldcop), CopLINE(oldcop)));
    }
  }

  LEAVE_DISARM_INFECT;

  return (SV *)trace;
}

#define make_traceav_copy(oann)  S_make_traceav_copy(aTHX_ oann)
static SV *S_make_traceav_copy(pTHX_ SV *oann)
{
  if(!SvMAGICAL(oann))
    return NULL;

  ENTER_DISARM_INFECT;
  MAGIC *omg = mg_findext(oann, PERL_MAGIC_ext, &vtbl_hound_debugtrace);
  assert(omg);

  AV *ntrace = newAV();

  AV *otrace = (AV *)omg->mg_obj;
  UV otrace_age = SvUV(AvARRAY(otrace)[0]);

  av_push(ntrace, newSVuv(otrace_age + 1));

  LEAVE_DISARM_INFECT;

  return (SV *)ntrace;
}
#endif /* DEBUG_TRACE_ANNOTATIONS */

/* Common mid-level functions, using low-level functions */
#define setup_hounding_magic(sv)  S_setup_hounding_magic(aTHX_ sv)
static MAGIC *S_setup_hounding_magic(pTHX_ SV *sv)
{
  assert(sv);

  MAGIC *mg = get_hounding_magic(sv);

  if (!mg)
    mg = add_hounding_magic(sv, newAV());

  return mg;
}

#define get_hounding_annotations(sv)  S_get_hounding_annotations(aTHX_ sv)
static AV *S_get_hounding_annotations(pTHX_ SV *sv)
{
  assert(sv);

  MAGIC *mg = get_hounding_magic(sv);
  if (!mg)
    return NULL;

  AV *annotations = get_hounding_av(mg);

  return annotations;
}

#define set_hounding_annotations(mg, sav, replace)  S_set_hounding_annotations(aTHX_ mg, sav, replace)
#define replace_hounding_annotations(mg, sav) set_hounding_annotations(mg, sav, true)
#define append_hounding_annotations(mg, sav) set_hounding_annotations(mg, sav, false)
static void S_set_hounding_annotations(pTHX_ MAGIC *mg, AV *sav, bool replace)
{
  assert(mg);
  assert(sav);

  AV *dav = get_hounding_av(mg);
  assert(dav);
  if (replace && av_count(dav))
    av_clear(dav);

  U32 count = av_count(sav);
  SV **svp = AvARRAY(sav);
  for(U32 idx = 0; idx < count; idx++) {
    SV *new = av_push_dup_if_uniq(dav, svp[idx]);
#ifdef DEBUG_TRACE_ANNOTATIONS
    // copying existing annotation: sv will always have debug tracing
    if(new) {
      sv_magicext(new, (SV *)make_traceav_copy(svp[idx]), PERL_MAGIC_ext, &vtbl_hound_debugtrace, NULL, 0);
    }
#endif
  }

}

#define append_hounding_annotation(mg, sv)  S_append_hounding_annotation(aTHX_ mg, sv)
static void S_append_hounding_annotation(pTHX_ MAGIC *mg, SV *sv)
{
  assert(mg);
  assert(sv);

  AV *dav = get_hounding_av(mg);
  assert(dav);

  SV *new = av_push_dup_if_uniq(dav, sv);
#ifdef DEBUG_TRACE_ANNOTATIONS
  // only called from hound_apply(): sv does not have debug tracing
  if(new) {
    sv_magicext(new, (SV *)make_traceav_orig(), PERL_MAGIC_ext, &vtbl_hound_debugtrace, NULL, 0);
  }
#endif
}

#define remove_hounding(sv)  S_remove_hounding(aTHX_ sv)
static void S_remove_hounding(pTHX_ SV *sv)
{
  assert(sv);

  remove_hounding_magic(sv);
}

#define set_hounding_magic(sv, annotations)  S_set_hounding_magic(aTHX_ sv, annotations)
static void S_set_hounding_magic(pTHX_ SV *sv, AV *annotations)
{
  assert(sv);

  MAGIC *mg = get_hounding_magic(sv);

  if (annotations) {
    if (mg) {
      replace_hounding_annotations(mg, annotations);
    } else {
      mg = setup_hounding_magic(sv);
      append_hounding_annotations(mg, annotations);
    }
  } else if (mg) {
    remove_hounding_magic(sv);
  }

  return;
}

#endif /* HAVE_HOUNDING */

/* Magic V2 hooks-based implementation */
#ifdef HAVE_MAGIC_V2

static const struct ScalarValueHookFunctions hound_hooks;
#define HOUND_HOOK_FUNCS ((struct HookFunctions *)&hound_hooks)

static MAGIC *S_get_hounding_magic(pTHX_ SV *sv)
{
  assert(sv);

  MAGIC *mg = NULL;
  if (SvTYPE(sv) >=  SVt_PVMG)
    mg = sv_hook_find_by_funcs(sv, HOUND_HOOK_FUNCS);

  return mg;
}

static MAGIC *S_add_hounding_magic(pTHX_ SV *sv, AV *av)
{
  assert(sv);
  assert(av);

  MAGIC *mg = sv_hook_add(sv, HOUND_HOOK_FUNCS, 0, (SV *)av);
  return mg;
}

static void S_remove_hounding_magic(pTHX_ SV *sv)
{
  assert(sv);

  sv_hook_remove_by_funcs(sv, HOUND_HOOK_FUNCS);
}

static AV *S_get_hounding_av(pTHX_ MAGIC *mg)
{
  assert(mg);

  AV *av = (AV *)HkAUXSV(mg);
  return av;
}

static void hounding_free(pTHX_ SV *sv, MAGIC *mg)
{
    AV *oav = (AV *)HkAUXSV(mg);
    if (oav)
      av_undef(oav);
}

static void hounding_infect(pTHX_ SV *osv, MAGIC *omg, SV *nsv, MAGIC *nmg)
{
  AV *oav = (AV *)HkAUXSV(omg);
  assert(oav);
  if (!av_count(oav))
    return;

  // create hook if needed: HKf_SCALARVALUE_INFECTIOUS not set, so no nmg
  MAGIC *mg = setup_hounding_magic(nsv);

  append_hounding_annotations(mg, oav);
}

static const struct ScalarValueHookFunctions hound_hooks = {
    .ver = 12345,    /* TODO */
    .shape = HKs_SCALARVALUE,
    .free = hounding_free,
    .infect = hounding_infect,

    /* FIXME: NEEDED?
    .clone = ...,
     */
};

#endif  /* HAVE_MAGIC_V2 */

/* USERTAINT-based implementation */
#ifdef HAVE_USERTAINT

static struct mgvtbl_with_copysv vtbl_hounding;
#define VTBL_HOUNDING ((MGVTBL *)&vtbl_hounding)

static MAGIC *S_get_hounding_magic(pTHX_ SV *sv)
{
  assert(sv);

  MAGIC *mg = NULL;
  if (SvTYPE(sv) >= SVt_PVMG) {
    mg = mg_findext(sv, PERL_MAGIC_extvalue, VTBL_HOUNDING);
  }

  return mg;
}

static MAGIC *S_add_hounding_magic(pTHX_ SV *sv, AV *av)
{
  assert(sv);
  assert(av);

  AV *annotations = newAV();
  MAGIC *mg = sv_magicext(sv, (SV *)annotations, PERL_MAGIC_extvalue, VTBL_HOUNDING, NULL, 0);
  mg->mg_flags |= MGf_COPYSV;

  return mg;
}

static void S_remove_hounding_magic(pTHX_ SV *sv)
{
  assert(sv);

  sv_unmagicext(sv, PERL_MAGIC_extvalue, VTBL_HOUNDING);
}

static AV *S_get_hounding_av(pTHX_ MAGIC *mg)
{
  assert(mg);

  AV *av = (AV *)mg->mg_obj;
  return av;
}

static int hounding_clear(pTHX_ SV *sv, MAGIC *mg)
{
  ENTER_DISARM_INFECT;

  sv_unmagicext(sv, PERL_MAGIC_extvalue, mg->mg_virtual);

  LEAVE_DISARM_INFECT;
  return 1;
}

static int hounding_copysv(pTHX_ SV *ssv, MAGIC *mg, SV *dsv)
{
  ENTER_DISARM_INFECT;

  AV *sav = (AV *)mg->mg_obj;
  assert(SvTYPE(sav) == SVt_PVAV);

  set_hounding_magic(dsv, sav);

  LEAVE_DISARM_INFECT;
  return 1;
}

static int hounding_get(pTHX_ SV *sv, MAGIC *mg)
{
  SV *dsv = PL_usertaint_annotations;

  ENTER_DISARM_INFECT;

  AV *sav = (AV *)mg->mg_obj;
  assert(SvTYPE(sav) == SVt_PVAV);

  if(!dsv)
    dsv = newSV(0);

  MAGIC *dmg = setup_hounding_magic(dsv);
  append_hounding_annotations(dmg, sav); // MUST copy tracing

  LEAVE_DISARM_INFECT;
  PL_usertaint_annotations = dsv;

  return 1;
}

static struct mgvtbl_with_copysv vtbl_hounding = {
  ._vtbl.svt_clear = hounding_clear,
  ._vtbl.svt_get   = hounding_get,
  .svt_copysv      = hounding_copysv,
};

#endif  /* HAVE_USERTAINT */

/* This is used to implement the dollar-digit regexp capture variables */

#ifdef HAVE_USERTAINT
static int postmatch_copyann_get(pTHX_ SV *sv, MAGIC *mg)
{
  REGEXP * const rx = PL_curpm ? PM_GETRE(PL_curpm) : NULL;
  if(!rx)
    return 1;

  ENTER_DISARM_INFECT;

  AV *sav = get_hounding_annotations((SV *)rx); // MUST copy tracing

  set_hounding_magic(sv, sav);

  LEAVE_DISARM_INFECT;

  return 1;
}

static const MGVTBL vtbl_postmatch_copyann = {
  .svt_get = &postmatch_copyann_get,
};

#define nparens_high_waterlevel(nparens)  S_nparens_high_waterlevel(aTHX_ nparens)
static void S_nparens_high_waterlevel(pTHX_ U32 nparens)
{
#ifdef MULTIPLICITY
  /* With MULTIPLICITY builds we need a unique value per interpreter; we'll
   * store it in PL_modglobal */
  SV *waterlevel_sv = *hv_fetchs(PL_modglobal, "Data::Hounding/nparens_high_waterlevel", GV_ADD);
  U32 waterlevel = SvIOK(waterlevel_sv) ? SvIV(waterlevel_sv) : 0;
#else
  /* We can take a shortcut. As there's only one, just keep it statically here
   */
  static U32 waterlevel;
#endif

  if(nparens <= waterlevel)
    return;

  for(U32 i = waterlevel; i < nparens; i++) {
    SV *varname = sv_2mortal(newSVpvf("%d", i+1)); /* register numbers are 1-based */
    SV *regbuf_var = get_sv(SvPV_nolen(varname), GV_ADD);

    sv_magicext(regbuf_var, NULL, PERL_MAGIC_ext, &vtbl_postmatch_copyann, NULL, 0);
  }

  waterlevel = nparens;
#ifdef MULTIPLICITY
  sv_setiv(waterlevel_sv, waterlevel);
#endif
}

#include "hounded_funcs.c.inc"

#endif /* HAVE_USERTAINT */

/* returns true if the comma-separated list of flags in 's' contains an exact
 * match for 'flag'
 */
static bool str_includes_flag(const char *s, const char *flag)
{
  STRLEN flaglen = strlen(flag);
  assert(flaglen);

  while(s && *s) {
    if(strncmp(s, flag, flaglen) == 0 &&
        (s[flaglen] == ',' || s[flaglen] == 0))
      return true;

    s = strchr(s, ',');
    if(!s)
      return false;
    while(*s == ',')
      s++;
  }
  return false;
}

MODULE = Data::Hounding    PACKAGE = Data::Hounding

void
hound_apply(SV *targref, SV *ann)
  CODE:
#ifdef HAVE_HOUNDING
    if(!SvROK(targref) || SvTYPE(SvRV(targref)) > SVt_PVMG)
      croak("Expected a SCALAR reference for target");
    if(!SvROK(ann))
      croak("Expected the annotation data to be a reference");

    MAGIC *mg = setup_hounding_magic(SvRV(targref));
    append_hounding_annotation(mg, ann); // will NOT have tracing
#endif

void
hound_query(SV *targref)
  PPCODE:
#ifdef HAVE_HOUNDING

    if(!SvROK(targref) || SvTYPE(SvRV(targref)) > SVt_PVMG)
      croak("Expected a SCALAR reference for target");

    AV *annotations = get_hounding_annotations(SvRV(targref));

    if(!annotations)
      XSRETURN(0);

    U32 count = av_count(annotations);
    SV **svp = AvARRAY(annotations);

    if(GIMME_V == G_VOID)
      Perl_ck_warner(aTHX_ packWARN(WARN_VOID),
        "Useless use of Data::Hounding::hound_query() in void context");

    if(GIMME_V <= G_SCALAR)
      XSRETURN_UV(count);

    EXTEND(SP, count);

    U32 idx;
    for(idx = 0; idx < count; idx++)
      PUSHs(sv_mortalcopy(svp[idx]));
    XSRETURN(count);
#else
    XSRETURN(0);
#endif

void
hound_delete(SV *targref)
  CODE:
#ifdef HAVE_HOUNDING
    if(!SvROK(targref) || SvTYPE(SvRV(targref)) > SVt_PVMG)
      croak("Expected a SCALAR reference for target");
    remove_hounding(SvRV(targref));
#endif

void
hound_tracing_enabled()
  CODE:
#ifdef DEBUG_TRACE_ANNOTATIONS
    XSRETURN(1);
#else
    XSRETURN(0);
#endif

BOOT:
#ifdef HAVE_HOUNDING
#  ifdef HAVE_USERTAINT
  const char *disable_flags = getenv("PERL_DATA_HOUNDING_DISABLE");
#    include "hounded_boot.c.inc"
#    ifdef HAVE_DMD_HELPER
  DMD_ADD_ROOT((SV *)&vtbl_hounding, "the Data::Hounding VTBL");
#    endif
#  endif
#  ifdef HAVE_MAGIC_V2
#    ifdef HAVE_DMD_HELPER
  DMD_ADD_ROOT((SV *)&hound_hooks, "the Data::Hounding Hook");
#    endif
#  endif
#  ifdef DEBUG_TRACE_ANNOTATIONS
  DMD_ADD_ROOT((SV *)&vtbl_hound_debugtrace, "the Data::Hounding debug trace VTBL");
#  endif
#endif
