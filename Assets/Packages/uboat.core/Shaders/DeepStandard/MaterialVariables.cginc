#ifndef UNITY_MATERIAL_VARIABLES_INCLUDED
#define UNITY_MATERIAL_VARIABLES_INCLUDED

#if defined(_TREE_LEAVES) || defined(_TREE_BARK)
	#define _TREE 1
#endif

#if defined(_TREE_LEAVES_MANUFACTURE) || defined(_TREE_BARK_MANUFACTURE)
	#define _TREE_MANUFACTURE 1
#endif

CBUFFER_START(UnityPerMaterial)
half4       _Color;
half        _Cutoff;

float4      _MainTex_ST;

float4      _DetailAlbedoMap_ST;

half        _BumpScale;

half        _DetailNormalMapScale;

half        _Metallic;
float       _Glossiness;
float       _GlossMapScale;

half        _OcclusionStrength;
half		_MipMapBiasMultiplier;

half        _Parallax;
half        _UVSec;

half4       _EmissionColor;

half4 _WetnessBiasScale;

half _DissolveMaskScale;
half _DissolveThreshold;

half _UVWetnessMap;

half _SubsurfaceScatteringIntensity;

#if defined(_LAYERED)
half4 _LayerCoords;
#endif

#if defined(_TREE)

half _TumbleStrength;
half _TumbleFrequency;
half _TimeOffset;
half _LeafTurbulence;
half _EdgeFlutterInfluence;

fixed4 _HueVariation;
half3 _TranslucencyStrength;

#endif

#if defined(_TREE_MANUFACTURE)

//fixed4 _ColorAutumn;
fixed4 _HueVariation;
fixed4 _HueVariationAutumn;

half3 _TranslucencyStrength;

#endif

#if defined(_HAIR)
float _HairOffset;
#endif

#if defined(DECAL_FULL)
fixed4 _PerChannelAlpha;
#endif

#if defined(_BILLBOARD)

fixed4 _HueVariation;
float _TreeHeightLimit;

#endif

#if defined (_MEGATEX)

half _NoiseDistanceFactor;
half _NoiseIntensity;
half _NoiseFrequency;
half _PatternRepeatDistance;
half _MegatexIntensity;

#endif

#if defined(LIGHTHOUSE_WINDOWS)
half _RotationOffset;
#endif

CBUFFER_END

#endif