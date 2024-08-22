// Unity built-in shader source. Copyright (c) 2016 Unity Technologies. MIT license (see license.txt)

#ifndef UNITY_STANDARD_INPUT_INCLUDED
#define UNITY_STANDARD_INPUT_INCLUDED

#include "UnityCG.cginc"
#include "UnityStandardConfig.cginc"
#include "UnityPBSLighting.cginc" // TBD: remove
#include "UnityStandardUtils.cginc"

//---------------------------------------
// Directional lightmaps & Parallax require tangent space too
#if (_NORMALMAP || DIRLIGHTMAP_COMBINED || _PARALLAXMAP)
    #define _TANGENT_TO_WORLD 1
#endif

#if (_DETAIL_MULX2 || _DETAIL_MUL || _DETAIL_ADD || _DETAIL_LERP)
    #define _DETAIL 1
#endif

#if defined(_TREE_MANUFACTURE) && defined(_DETAIL_MULX2)
    #undef _DETAIL_MULX2
    #define _DETAIL_LERP 1
#endif

//---------------------------------------

#include "MaterialVariables.cginc"

sampler2D   _MainTex;
sampler2D   _DetailAlbedoMap;
sampler2D   _BumpMap;
sampler2D   _DetailMask;
sampler2D   _DetailNormalMap;
sampler2D   _SpecGlossMap;
sampler2D   _MetallicGlossMap;
sampler2D   _SnowAlbedo;
sampler2D   _ParallaxMap;
sampler2D   _EmissionMap;
sampler2D   _WetnessMap;

#if defined(_LAYERED)
sampler2D   _LayerAlbedo;
#endif

#if defined(_TREE)
sampler2D   _BumpSpecAOMap;
sampler2D   _TranslucencyMap;
#endif

#if defined(_TREE_MANUFACTURE)
sampler2D   _DetailMetallicGlossMap;
#endif

#if defined(_TREE_LEAVES_MANUFACTURE)
half _SeasonBlendFactor;
#endif

half _GlobalMipMapBias;

//-------------------------------------------------------------------------------------
// Input functions

#if defined(TESSELATION)
struct TesselatorVertexInput
{
	float4 vertex		: INTERNALTESSPOS;
	float tessFactor : TEXCOORD1;
    half3 normal    : NORMAL;
    float2 uv0      : TEXCOORD0;
#if defined(_TREE) || defined(_TREE_MANUFACTURE) || defined(_BILLBOARD)
    float4 uv1      : TEXCOORD2;
#else
    float2 uv1      : TEXCOORD2;
#endif

#if defined(_TREE) || defined(_BILLBOARD)
    fixed4 color    : COLOR0;
    float3 uv2      : TEXCOORD3;
#else
	#if defined(_TREE_MANUFACTURE)
		fixed4 color    : COLOR0;
	#endif

	#if defined(DYNAMICLIGHTMAP_ON) || defined(UNITY_PASS_META) || defined(_DAMAGE_MAP) || defined(_SIMPLE_WATER)
		float2 uv2      : TEXCOORD3;
	#endif
#endif
#ifdef _TANGENT_TO_WORLD
    half4 tangent   : TANGENT;
#endif
    UNITY_VERTEX_INPUT_INSTANCE_ID
};
#endif

struct VertexInput
{
    float4 vertex   : POSITION;
    half3 normal    : NORMAL;
    float2 uv0      : TEXCOORD0;
#if defined(_TREE) || defined(_BILLBOARD)
    float4 uv1      : TEXCOORD1;
#elif defined(_TREE_MANUFACTURE)
    float4 uv1      : TEXCOORD2;
#else
    float2 uv1      : TEXCOORD1;
#endif

#if defined(_TREE) || defined(_BILLBOARD)
    fixed4 color    : COLOR0;
    float3 uv2      : TEXCOORD2;
#elif defined(_TREE_MANUFACTURE)
    fixed4 color    : COLOR0;
#elif defined(DYNAMICLIGHTMAP_ON) || defined(UNITY_PASS_META) || defined(_DAMAGE_MAP) || defined(_SIMPLE_WATER)
    float2 uv2      : TEXCOORD2;
#endif
#ifdef _TANGENT_TO_WORLD
    half4 tangent   : TANGENT;
#endif

#ifdef _FLAG
	uint id : SV_VertexID;
#endif

    UNITY_VERTEX_INPUT_INSTANCE_ID
};

float4 TexCoords(VertexInput v)
{
    float4 texcoord;
    texcoord.xy = TRANSFORM_TEX(v.uv0, _MainTex); // Always source from uv0
    texcoord.zw = TRANSFORM_TEX(((_UVSec == 0) ? v.uv0 : v.uv1), _DetailAlbedoMap);
    return texcoord;
}

half DetailMask(float2 uv)
{
    return tex2D (_DetailMask, uv).a;
}

half3 Albedo(float4 texcoords)
{
//#if defined(_TREE_LEAVES_MANUFACTURE)
//    half3 albedo = lerp(_Color.rgb, _ColorAutumn.rgb, _SeasonBlendFactor) * tex2D (_MainTex, texcoords.xy).rgb;
//#else
    half3 albedo = _Color.rgb * tex2Dbias (_MainTex, float4(texcoords.xy, 0, _GlobalMipMapBias * _MipMapBiasMultiplier)).rgb;
//#endif
#if _LAYERED
	half4 layerAlbedo = tex2D(_LayerAlbedo, texcoords.xy * _LayerCoords.xy + _LayerCoords.zw);
	albedo.rgb = lerp(albedo.rgb, layerAlbedo.rgb, layerAlbedo.a);
#endif
#if _DETAIL
    #if (SHADER_TARGET < 30)
        // SM20: instruction count limitation
        // SM20: no detail mask
        half mask = 1;
    #else
        half mask = DetailMask(texcoords.xy);
    #endif
    half3 detailAlbedo = tex2D (_DetailAlbedoMap, texcoords.zw).rgb;
    #if _DETAIL_MULX2
        albedo *= LerpWhiteTo (detailAlbedo * unity_ColorSpaceDouble.rgb, mask);
    #elif _DETAIL_MUL
        albedo *= LerpWhiteTo (detailAlbedo, mask);
    #elif _DETAIL_ADD
        albedo += detailAlbedo * mask;
    #elif _DETAIL_LERP
        albedo = lerp (albedo, _Color.rgb * detailAlbedo, mask);
    #endif
#endif
    return albedo;
}

half Alpha(float2 uv)
{
#if defined(_SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A)
    return _Color.a;
#else
    return tex2Dbias(_MainTex, float4(uv.xy, 0, _GlobalMipMapBias * _MipMapBiasMultiplier)).a * _Color.a;
#endif
}

half Occlusion(float2 uv)
{
#ifdef _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
    #if (SHADER_TARGET < 30)
        // SM20: instruction count limitation
        // SM20: simpler occlusion
        return tex2D(_MetallicGlossMap, uv).r;
    #else
        half occ = tex2D(_MetallicGlossMap, uv).r;
        return LerpOneTo (occ, _OcclusionStrength);
    #endif
#else
    #if (SHADER_TARGET < 30)
        // SM20: instruction count limitation
        // SM20: simpler occlusion
        return tex2D(_MetallicGlossMap, uv).g;
    #else
        half occ = tex2D(_MetallicGlossMap, uv).g;
        return LerpOneTo (occ, _OcclusionStrength);
    #endif
#endif
}

half4 SpecularGloss(float2 uv)
{
    half4 sg;
#ifdef _SPECGLOSSMAP
    #if defined(_SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A)
        sg.rgb = tex2D(_SpecGlossMap, uv).rgb;
        sg.a = tex2D(_MainTex, uv).a;
    #else
        sg = tex2D(_SpecGlossMap, uv);
    #endif
    sg.a *= _GlossMapScale;
#else
    sg.rgb = _SpecColor.rgb;
    #ifdef _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
        sg.a = tex2D(_MainTex, uv).a * _GlossMapScale;
    #else
        sg.a = _Glossiness;
    #endif
#endif
    return sg;
}

#if defined(_TREE_MANUFACTURE) && _DETAIL
half2 MetallicGloss(float4 uv)
#else
half2 MetallicGloss(float2 uv)
#endif
{
    half2 mg;

#ifdef _METALLICGLOSSMAP
    #ifdef _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
        mg.r = _Metallic;
        mg.g = tex2D(_MainTex, uv).a;
    #else
        mg = tex2D(_MetallicGlossMap, uv).ra;
    #endif
    mg.g *= _GlossMapScale;
#else
    mg.r = _Metallic;
    #ifdef _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
        mg.g = tex2D(_MainTex, uv).a * _GlossMapScale;
    #else
        mg.g = _Glossiness;
    #endif
#endif

#if defined(_TREE_MANUFACTURE)
    mg.r = 0.0;

#if _DETAIL
    half mask = DetailMask(uv.xy);
    half detailMG = tex2D (_DetailMetallicGlossMap, uv.zw).a;
    mg.g = lerp(mg.g, detailMG, mask);
#endif
#endif

    return mg;
}

half2 MetallicRough(float2 uv)
{
    half2 mg;
#ifdef _METALLICGLOSSMAP
    mg.r = tex2Dbias(_MetallicGlossMap, float4(uv, 0, _GlobalMipMapBias * _MipMapBiasMultiplier)).r;
#else
    mg.r = _Metallic;
#endif

#ifdef _SPECGLOSSMAP
    mg.g = 1.0f - tex2Dbias(_SpecGlossMap, float4(uv, 0, _GlobalMipMapBias * _MipMapBiasMultiplier)).r;
#else
    mg.g = 1.0f - _Glossiness;
#endif

    return mg;
}

half3 Emission(float2 uv)
{
#ifndef _EMISSION
    return 0;
#else
    return tex2D(_EmissionMap, uv).rgb * _EmissionColor.rgb;
#endif
}

#ifdef _NORMALMAP
half3 NormalInTangentSpace(float4 texcoords)
{
#if defined(_TREE)
    #if defined(_SWAP_UVS)
        half3 normalTangent = UnpackScaleNormal(tex2D (_BumpSpecAOMap, texcoords.zw), _BumpScale);
    #else
        half3 normalTangent = UnpackScaleNormal(tex2D (_BumpSpecAOMap, texcoords.xy), _BumpScale);
    #endif
#else
    half3 normalTangent = UnpackScaleNormal(tex2Dbias (_BumpMap, float4(texcoords.xy, 0, _GlobalMipMapBias * _MipMapBiasMultiplier)), _BumpScale);
#endif

#if _DETAIL && defined(UNITY_ENABLE_DETAIL_NORMALMAP)
    half mask = DetailMask(texcoords.xy);
    half3 detailNormalTangent = UnpackScaleNormal(tex2D (_DetailNormalMap, texcoords.zw), _DetailNormalMapScale);
    #if _DETAIL_LERP
        normalTangent = lerp(
            normalTangent,
            detailNormalTangent,
            mask);
    #else
        normalTangent = lerp(
            normalTangent,
            BlendNormals(normalTangent, detailNormalTangent),
            mask);
    #endif
#endif

    return normalTangent;
}
#endif

float4 Parallax (float4 texcoords, half3 viewDir)
{
#if !defined(_PARALLAXMAP) || (SHADER_TARGET < 30)
    // Disable parallax on pre-SM3.0 shader target models
    return texcoords;
#else
    half h = tex2D (_ParallaxMap, texcoords.xy).r;
    float2 offset = ParallaxOffset1Step (h, _Parallax, viewDir);
    return float4(texcoords.xy + offset, texcoords.zw + offset);
#endif

}

#endif // UNITY_STANDARD_INPUT_INCLUDED
