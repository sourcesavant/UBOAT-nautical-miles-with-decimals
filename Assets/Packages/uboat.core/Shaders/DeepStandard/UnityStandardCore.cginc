// Unity built-in shader source. Copyright (c) 2016 Unity Technologies. MIT license (see license.txt)

#ifndef UNITY_STANDARD_CORE_INCLUDED
#define UNITY_STANDARD_CORE_INCLUDED

#include "MaterialVariables.cginc"
#include "UnityCG.cginc"
#include "UnityGlobalIllumination.cginc"
#include "UnityShaderVariables.cginc"
#include "UnityStandardConfig.cginc"
#include "UnityStandardInput.cginc"
#include "UnityPBSLighting.cginc"
#include "UnityStandardUtils.cginc"
#include "UnityGBuffer.cginc"
#include "UnityStandardBRDF.cginc"

#include "AutoLight.cginc"

float4 _FarRenderingParams;
half4 _TransparencyFogColor;
half _VolumetricIntensity;

sampler2D _VolumetricLightingTex;
sampler2D _CameraDepthTexture;

//-------------------------------------------------------------------------------------
// counterpart for NormalizePerPixelNormal
// skips normalization per-vertex and expects normalization to happen per-pixel
half3 NormalizePerVertexNormal (float3 n) // takes float to avoid overflow
{
    #if (SHADER_TARGET < 30) || UNITY_STANDARD_SIMPLE
        return normalize(n);
    #else
        return n; // will normalize per-pixel instead
    #endif
}

float3 NormalizePerPixelNormal (float3 n)
{
    #if (SHADER_TARGET < 30) || UNITY_STANDARD_SIMPLE
        return n;
    #else
        return normalize(n);
    #endif
}

//-------------------------------------------------------------------------------------

UnityLight AdditiveLight (half3 lightDir, half atten)
{
    UnityLight l;

    l.color = _LightColor0.rgb;
    l.dir = lightDir;
    #ifndef USING_DIRECTIONAL_LIGHT
        l.dir = NormalizePerPixelNormal(l.dir);
    #endif

    // shadow the light
    l.color *= atten;
    return l;
}

UnityLight DummyLight ()
{
    UnityLight l;
    l.color = 0;
    l.dir = half3 (0,1,0);
    return l;
}

UnityIndirect ZeroIndirect ()
{
    UnityIndirect ind;
    ind.diffuse = 0;
    ind.specular = 0;
    return ind;
}

//-------------------------------------------------------------------------------------
// Common fragment setup

// deprecated
half3 WorldNormal(half4 tan2world[3])
{
    return normalize(tan2world[2].xyz);
}

// deprecated
#ifdef _TANGENT_TO_WORLD
    half3x3 ExtractTangentToWorldPerPixel(half4 tan2world[3])
    {
        half3 t = tan2world[0].xyz;
        half3 b = tan2world[1].xyz;
        half3 n = tan2world[2].xyz;

    #if UNITY_TANGENT_ORTHONORMALIZE
        n = NormalizePerPixelNormal(n);

        // ortho-normalize Tangent
        t = normalize (t - n * dot(t, n));

        // recalculate Binormal
        half3 newB = cross(n, t);
        b = newB * sign (dot (newB, b));
    #endif

        return half3x3(t, b, n);
    }
#else
    half3x3 ExtractTangentToWorldPerPixel(half4 tan2world[3])
    {
        return half3x3(0,0,0,0,0,0,0,0,0);
    }
#endif

#ifdef _PARALLAXMAP
    #define IN_VIEWDIR4PARALLAX(i) NormalizePerPixelNormal(half3(i.tangentToWorldAndPackedData[0].w,i.tangentToWorldAndPackedData[1].w,i.tangentToWorldAndPackedData[2].w))
    #define IN_VIEWDIR4PARALLAX_FWDADD(i) NormalizePerPixelNormal(i.viewDirForParallax.xyz)
#else
    #define IN_VIEWDIR4PARALLAX(i) half3(0,0,0)
    #define IN_VIEWDIR4PARALLAX_FWDADD(i) half3(0,0,0)
#endif

#define UNITY_REQUIRE_FRAG_WORLDPOS 1

#if UNITY_REQUIRE_FRAG_WORLDPOS
    #if UNITY_PACK_WORLDPOS_WITH_TANGENT
        #define IN_WORLDPOS(i) half3(i.tangentToWorldAndPackedData[0].w,i.tangentToWorldAndPackedData[1].w,i.tangentToWorldAndPackedData[2].w)
    #else
        #define IN_WORLDPOS(i) i.posWorld
    #endif
    #define IN_WORLDPOS_FWDADD(i) i.posWorld
#else
    #define IN_WORLDPOS(i) half3(0,0,0)
    #define IN_WORLDPOS_FWDADD(i) half3(0,0,0)
#endif

#define IN_LIGHTDIR_FWDADD(i) half3(i.tangentToWorldAndLightDir[0].w, i.tangentToWorldAndLightDir[1].w, i.tangentToWorldAndLightDir[2].w)

#define FRAGMENT_SETUP(x) FragmentCommonData x = \
    FragmentSetup(i.tex, i.eyeVec, IN_VIEWDIR4PARALLAX(i), i.tangentToWorldAndPackedData, IN_WORLDPOS(i));

#define FRAGMENT_SETUP_FWDADD(x) FragmentCommonData x = \
    FragmentSetup(i.tex, i.eyeVec, IN_VIEWDIR4PARALLAX_FWDADD(i), i.tangentToWorldAndLightDir, IN_WORLDPOS_FWDADD(i));

struct FragmentCommonData
{
    half3 diffColor, specColor;
    // Note: smoothness & oneMinusReflectivity for optimization purposes, mostly for DX9 SM2.0 level.
    // Most of the math is being done on these (1-x) values, and that saves a few precious ALU slots.
    half oneMinusReflectivity, smoothness;
    float3 normalWorld;
    float3 eyeVec;
    half alpha;
    float3 posWorld;

#if UNITY_STANDARD_SIMPLE
    half3 reflUVW;
#endif

#if UNITY_STANDARD_SIMPLE
    half3 tangentSpaceNormal;
#endif
};

// EDITS START
#include "DeepStandardLib.cginc"
// EDITS END

float3 PerPixelWorldNormal(float4 i_tex, float4 tangentToWorld[3], float3 i_posWorld)
{
#ifdef _NORMALMAP
    half3 tangent = tangentToWorld[0].xyz;
    half3 binormal = tangentToWorld[1].xyz;
    half3 normal = tangentToWorld[2].xyz;

    #if UNITY_TANGENT_ORTHONORMALIZE
        normal = NormalizePerPixelNormal(normal);

        // ortho-normalize Tangent
        tangent = normalize (tangent - normal * dot(tangent, normal));

        // recalculate Binormal
        half3 newB = cross(normal, tangent);
        binormal = newB * sign (dot (newB, binormal));
    #endif

#if defined(_SIMPLE_WATER)
    half3 normalTangent = GetWaterNormals(i_tex, i_posWorld);
#else
	half3 normalTangent = NormalInTangentSpace(i_tex);
#endif

    float3 normalWorld = NormalizePerPixelNormal(tangent * normalTangent.x + binormal * normalTangent.y + normal * normalTangent.z); // @TODO: see if we can squeeze this normalize on SM2.0 as well
#else
    float3 normalWorld = normalize(tangentToWorld[2].xyz);
#endif
    return normalWorld;
}

#ifndef UNITY_SETUP_BRDF_INPUT
    #define UNITY_SETUP_BRDF_INPUT SpecularSetup
#endif

inline FragmentCommonData SpecularSetup (float4 i_tex)
{
    half4 specGloss = SpecularGloss(i_tex.xy);
    half3 specColor = specGloss.rgb;
    half smoothness = specGloss.a;

    half oneMinusReflectivity;
    half3 diffColor = EnergyConservationBetweenDiffuseAndSpecular (Albedo(i_tex), specColor, /*out*/ oneMinusReflectivity);

    FragmentCommonData o = (FragmentCommonData)0;
    o.diffColor = diffColor;
    o.specColor = specColor;
    o.oneMinusReflectivity = oneMinusReflectivity;
    o.smoothness = smoothness;
    return o;
}

inline FragmentCommonData RoughnessSetup(float4 i_tex)
{
    half2 metallicGloss = MetallicRough(i_tex.xy);
    half metallic = metallicGloss.x;
    half smoothness = metallicGloss.y; // this is 1 minus the square root of real roughness m.

    half oneMinusReflectivity;
    half3 specColor;
    half3 diffColor = DiffuseAndSpecularFromMetallic(Albedo(i_tex), metallic, /*out*/ specColor, /*out*/ oneMinusReflectivity);

    FragmentCommonData o = (FragmentCommonData)0;
    o.diffColor = diffColor;
    o.specColor = specColor;
    o.oneMinusReflectivity = oneMinusReflectivity;
    o.smoothness = smoothness;
    return o;
}

inline FragmentCommonData MetallicSetup (float4 i_tex)
{
    half2 metallicGloss = MetallicGloss(i_tex);
    half metallic = metallicGloss.x;
    half smoothness = metallicGloss.y; // this is 1 minus the square root of real roughness m.

    half oneMinusReflectivity;
    half3 specColor;
    half3 diffColor = DiffuseAndSpecularFromMetallic (Albedo(i_tex), metallic, /*out*/ specColor, /*out*/ oneMinusReflectivity);

    FragmentCommonData o = (FragmentCommonData)0;
    o.diffColor = diffColor;
    o.specColor = specColor;
    o.oneMinusReflectivity = oneMinusReflectivity;
    o.smoothness = smoothness;
    return o;
}

float PerceptualRoughnessToRoughness2(float perceptualRoughness)
{
	return perceptualRoughness * perceptualRoughness;
}

float RoughnessToPerceptualRoughness2(float roughness)
{
	return sqrt(roughness);
}

float RoughnessToPerceptualSmoothness2(float roughness)
{
	return 1.0 - sqrt(roughness);
}

float PerceptualSmoothnessToRoughness2(float perceptualSmoothness)
{
	return (1.0 - perceptualSmoothness) * (1.0 - perceptualSmoothness);
}

float PerceptualSmoothnessToPerceptualRoughness2(float perceptualSmoothness)
{
	return (1.0 - perceptualSmoothness);
}

// Return modified perceptualSmoothness based on provided variance (get from GeometricNormalVariance + TextureNormalVariance)
float NormalFiltering(float perceptualSmoothness, float variance, float threshold)
{
	float roughness = PerceptualSmoothnessToRoughness2(perceptualSmoothness);
	// Ref: Geometry into Shading - http://graphics.pixar.com/library/BumpRoughness/paper.pdf - equation (3)
	float squaredRoughness = saturate(roughness * roughness + min(2.0 * variance, threshold * threshold)); // threshold can be really low, square the value for easier control

	return RoughnessToPerceptualSmoothness2(sqrt(squaredRoughness));
}

// Reference: Error Reduction and Simplification for Shading Anti-Aliasing
// Specular antialiasing for geometry-induced normal (and NDF) variations: Tokuyoshi / Kaplanyan et al.'s method.
// This is the deferred approximation, which works reasonably well so we keep it for forward too for now.
// screenSpaceVariance should be at most 0.5^2 = 0.25, as that corresponds to considering
// a gaussian pixel reconstruction kernel with a standard deviation of 0.5 of a pixel, thus 2 sigma covering the whole pixel.
float GeometricNormalVariance(float3 geometricNormalWS, float screenSpaceVariance)
{
	float3 deltaU = ddx(geometricNormalWS);
	float3 deltaV = ddy(geometricNormalWS);

	return screenSpaceVariance * (dot(deltaU, deltaU) + dot(deltaV, deltaV));
}

// Return modified perceptualSmoothness
float GeometricNormalFiltering(float perceptualSmoothness, float3 geometricNormalWS, float screenSpaceVariance, float threshold)
{
	float variance = GeometricNormalVariance(geometricNormalWS, screenSpaceVariance);
	return NormalFiltering(perceptualSmoothness, variance, threshold);
}

// parallax transformed texcoord is used to sample occlusion
inline FragmentCommonData FragmentSetup (inout float4 i_tex, float3 i_eyeVec, half3 i_viewDirForParallax, float4 tangentToWorld[3], float3 i_posWorld)
{
    i_tex = Parallax(i_tex, i_viewDirForParallax);

    half alpha = Alpha(i_tex.xy);
    #if defined(_ALPHATEST_ON)
        clip (alpha - _Cutoff);
    #endif

    FragmentCommonData o = UNITY_SETUP_BRDF_INPUT (i_tex);
    o.normalWorld = PerPixelWorldNormal(i_tex, tangentToWorld, i_posWorld);
    o.eyeVec = NormalizePerPixelNormal(i_eyeVec);
    o.posWorld = i_posWorld;

    // NOTE: shader relies on pre-multiply alpha-blend (_SrcBlend = One, _DstBlend = OneMinusSrcAlpha)
    o.diffColor = PreMultiplyAlpha (o.diffColor, alpha, o.oneMinusReflectivity, /*out*/ o.alpha);

	// specular geometric AA
	o.smoothness = GeometricNormalFiltering(o.smoothness, o.normalWorld, 0.235, 0.53);

    return o;
}

inline UnityGI FragmentGI (FragmentCommonData s, half occlusion, half4 i_ambientOrLightmapUV, half atten, UnityLight light, bool reflections)
{
    UnityGIInput d;
    d.light = light;
    d.worldPos = s.posWorld;
    d.worldViewDir = -s.eyeVec;
    d.atten = atten;
    #if defined(LIGHTMAP_ON) || defined(DYNAMICLIGHTMAP_ON)
        d.ambient = 0;
        d.lightmapUV = i_ambientOrLightmapUV;
    #else
        d.ambient = i_ambientOrLightmapUV.rgb;
        d.lightmapUV = 0;
    #endif

    d.probeHDR[0] = unity_SpecCube0_HDR;
    d.probeHDR[1] = unity_SpecCube1_HDR;
    #if defined(UNITY_SPECCUBE_BLENDING) || defined(UNITY_SPECCUBE_BOX_PROJECTION)
      d.boxMin[0] = unity_SpecCube0_BoxMin; // .w holds lerp value for blending
    #endif
    #ifdef UNITY_SPECCUBE_BOX_PROJECTION
      d.boxMax[0] = unity_SpecCube0_BoxMax;
      d.probePosition[0] = unity_SpecCube0_ProbePosition;
      d.boxMax[1] = unity_SpecCube1_BoxMax;
      d.boxMin[1] = unity_SpecCube1_BoxMin;
      d.probePosition[1] = unity_SpecCube1_ProbePosition;
    #endif

    if(reflections)
    {
        Unity_GlossyEnvironmentData g = UnityGlossyEnvironmentSetup(s.smoothness, -s.eyeVec, s.normalWorld, s.specColor);
        // Replace the reflUVW if it has been compute in Vertex shader. Note: the compiler will optimize the calcul in UnityGlossyEnvironmentSetup itself
        #if UNITY_STANDARD_SIMPLE
            g.reflUVW = s.reflUVW;
        #endif

        return UnityGlobalIllumination (d, occlusion, s.normalWorld, g);
    }
    else
    {
        return UnityGlobalIllumination (d, occlusion, s.normalWorld);
    }
}

inline UnityGI FragmentGI (FragmentCommonData s, half occlusion, half4 i_ambientOrLightmapUV, half atten, UnityLight light)
{
    return FragmentGI(s, occlusion, i_ambientOrLightmapUV, atten, light, true);
}


//-------------------------------------------------------------------------------------
half4 OutputForward (half4 output, half alphaFromSurface)
{
    #if defined(_ALPHABLEND_ON) || defined(_ALPHAPREMULTIPLY_ON)
        output.a = alphaFromSurface;
    #else
        UNITY_OPAQUE_ALPHA(output.a);
    #endif
    return output;
}

inline half4 VertexGIForward(VertexInput v, float3 posWorld, half3 normalWorld)
{
    half4 ambientOrLightmapUV = 0;
    // Static lightmaps
    #ifdef LIGHTMAP_ON
        ambientOrLightmapUV.xy = v.uv1.xy * unity_LightmapST.xy + unity_LightmapST.zw;
        ambientOrLightmapUV.zw = 0;
    // Sample light probe for Dynamic objects only (no static or dynamic lightmaps)
    #elif UNITY_SHOULD_SAMPLE_SH
        #ifdef VERTEXLIGHT_ON
            // Approximated illumination from non-important point lights
            ambientOrLightmapUV.rgb = Shade4PointLights (
                unity_4LightPosX0, unity_4LightPosY0, unity_4LightPosZ0,
                unity_LightColor[0].rgb, unity_LightColor[1].rgb, unity_LightColor[2].rgb, unity_LightColor[3].rgb,
                unity_4LightAtten0, posWorld, normalWorld);
        #endif

        ambientOrLightmapUV.rgb = ShadeSHPerVertex (normalWorld, ambientOrLightmapUV.rgb);
    #endif

    #if defined(DYNAMICLIGHTMAP_ON)
        ambientOrLightmapUV.zw = v.uv2.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
    #endif

    return ambientOrLightmapUV;
}

// ------------------------------------------------------------------
//  Base forward pass (directional light, emission, lightmaps, ...)

struct VertexOutputForwardBase
{
    UNITY_POSITION(pos);
    float4 tex                            : TEXCOORD0;
    float3 eyeVec                         : TEXCOORD1;
    float4 tangentToWorldAndPackedData[3] : TEXCOORD2;    // [3x3:tangentToWorld | 1x3:viewDirForParallax or worldPos]
    half4 ambientOrLightmapUV             : TEXCOORD5;    // SH or Lightmap UV
#if !defined (UNITY_HALF_PRECISION_FRAGMENT_SHADER_REGISTERS)
    UNITY_SHADOW_COORDS(6)
#else
    UNITY_LIGHTING_COORDS(6,7)
#endif
        // next ones would not fit into SM2.0 limits, but they are always for SM3.0+
    #if UNITY_REQUIRE_FRAG_WORLDPOS && !UNITY_PACK_WORLDPOS_WITH_TANGENT
        float3 posWorld                 : TEXCOORD8;
    #endif

	half4 screenPos						: TEXCOORD9;

    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

VertexOutputForwardBase vertForwardBase (VertexInput v)
{
    UNITY_SETUP_INSTANCE_ID(v);
    VertexOutputForwardBase o;
    UNITY_INITIALIZE_OUTPUT(VertexOutputForwardBase, o);
    UNITY_TRANSFER_INSTANCE_ID(v, o);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

#if defined(_BILLBOARD)
    AFSBillboardVert_DWS(/*inout*/ v);
#endif

#if defined(_TREE_LEAVES)
    float3 pivot;

	// 15bit compression 2 components only, important: sign of y
	pivot.xz = (frac(float2(1.0f, 32768.0f) * v.uv2.xx) * 2) - 1;
	pivot.y = sqrt(1 - saturate(dot(pivot.xz, pivot.xz)));
	pivot *= v.uv2.y;
	#if !defined(IS_LODTREE)
		pivot *= _TreeInstanceScale.xyz;
	#endif

	float4 TerrainLODWind = _TerrainLODWind;
	TerrainLODWind.xyz = mul((float3x3)unity_WorldToObject, _TerrainLODWind.xyz);
	CTI_AnimateVertex_DWS( v, float4(v.vertex.xyz, v.color.b), v.normal, float4(v.color.xy, v.uv1.xy), pivot, v.color.b, TerrainLODWind, v.uv2.z);
#elif defined(_TREE_BARK)
    float4 TerrainLODWind = _TerrainLODWind;
	TerrainLODWind.xyz = mul((float3x3)unity_WorldToObject, _TerrainLODWind.xyz);
	CTI_AnimateVertex_DWS( v, float4(v.vertex.xyz, v.color.b), v.normal, float4(v.color.xy, v.uv1.xy), float3(0,0,0), 0, TerrainLODWind, 0); //v.uv2.z);
#elif defined(_TREE_LEAVES_MANUFACTURE) || defined(_TREE_BARK_MANUFACTURE)
    CalculateWind(v);
#endif

    float4 posWorld = mul(unity_ObjectToWorld, v.vertex);

#if defined(USE_CUSTOM_AMBIENT) && !defined(_BILLBOARD)			// apply earth curvature effect only to exterior meshes
	posWorld = CompensateForEarthCurvature(posWorld);
#endif

#if defined(_SIMPLE_WATER)
	v.vertex.y -= max(0.0, posWorld.y - _ClipHeight);
	posWorld.y = min(posWorld.y, _ClipHeight);
#endif

#if defined(DECAL)
    v.vertex.xyz += v.normal * 0.001;
#endif

    #if UNITY_REQUIRE_FRAG_WORLDPOS
        #if UNITY_PACK_WORLDPOS_WITH_TANGENT
            o.tangentToWorldAndPackedData[0].w = posWorld.x;
            o.tangentToWorldAndPackedData[1].w = posWorld.y;
            o.tangentToWorldAndPackedData[2].w = posWorld.z;
        #else
            o.posWorld = posWorld.xyz;
        #endif
    #endif

	float3 normalWorld = UnityObjectToWorldNormal(v.normal);

#if defined(_HAIR)
	posWorld.xyz += normalWorld * _HairOffset;
#endif

    o.pos = mul(UNITY_MATRIX_VP, posWorld);

#if defined(_BILLBOARD)
    o.pos = UnityObjectToClipPos(v.vertex);
#endif

    o.tex = TexCoords(v);
    o.eyeVec = NormalizePerVertexNormal(posWorld.xyz - _WorldSpaceCameraPos);
	o.screenPos = ComputeScreenPos(o.pos);
    #ifdef _TANGENT_TO_WORLD
        float4 tangentWorld = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);

        float3x3 tangentToWorld = CreateTangentToWorldPerVertex(normalWorld, tangentWorld.xyz, tangentWorld.w);
        o.tangentToWorldAndPackedData[0].xyz = tangentToWorld[0];
        o.tangentToWorldAndPackedData[1].xyz = tangentToWorld[1];
        o.tangentToWorldAndPackedData[2].xyz = tangentToWorld[2];
    #else
        o.tangentToWorldAndPackedData[0].xyz = 0;
        o.tangentToWorldAndPackedData[1].xyz = 0;
        o.tangentToWorldAndPackedData[2].xyz = normalWorld;
    #endif

    //We need this for shadow receving
    UNITY_TRANSFER_LIGHTING(o, v.uv1);

    o.ambientOrLightmapUV = VertexGIForward(v, posWorld, normalWorld);

#if defined(_BILLBOARD)
    o.ambientOrLightmapUV.w = v.color.r;
#elif defined(_TREE_LEAVES_MANUFACTURE)
    float hueVariationAmount = frac(dot(unity_ObjectToWorld._m03_m13_m23, 1));
	o.ambientOrLightmapUV.w = saturate(hueVariationAmount * lerp(_HueVariation.a, _HueVariationAutumn.a, _SeasonBlendFactor));
#endif

    #ifdef _PARALLAXMAP
        TANGENT_SPACE_ROTATION;
        half3 viewDirForParallax = mul (rotation, ObjSpaceViewDir(v.vertex));
        o.tangentToWorldAndPackedData[0].w = viewDirForParallax.x;
        o.tangentToWorldAndPackedData[1].w = viewDirForParallax.y;
        o.tangentToWorldAndPackedData[2].w = viewDirForParallax.z;
    #endif

    #ifdef USE_CUSTOM_AMBIENT
        float finalDepth = o.pos.z / abs(o.pos.w);

	    if(finalDepth < _FarRenderingParams.x)
	    {
		    float correctedDepth = finalDepth * _FarRenderingParams.z + _FarRenderingParams.y;
		    o.pos.z = correctedDepth * abs(o.pos.w);
	    }
    #endif

    return o;
}


// SRP START ----
#define MAX_VISIBLE_LIGHTS 32

int _DirectionalLightsCount;

CBUFFER_START(_PerCamera)
	half4 _LightCount;
	int _LightShadowIndices[MAX_VISIBLE_LIGHTS];
	float4 _LightPosition[MAX_VISIBLE_LIGHTS];
	half4 _LightListColor[MAX_VISIBLE_LIGHTS];
	half4 _LightDistanceAttenuation[MAX_VISIBLE_LIGHTS];
	half4 _LightSpotDir[MAX_VISIBLE_LIGHTS];
CBUFFER_END

struct DeepLight
{
	half4 distanceAttenuation;
	half3 color;
	float3 dir;
};

StructuredBuffer<int> _LightIndexBuffer;

#include "LightingTemplate.hlsl"

DeepLight GetLight(int index)
{
	DeepLight light;

	light.distanceAttenuation = _LightDistanceAttenuation[index];
	light.color = _LightListColor[index];
	light.dir = _LightPosition[index];

	return light;
}

half DistanceAttenuation(half distanceSqr, half3 distanceAttenuation)
{
	// We use a shared distance attenuation for additional directional and puctual lights
	// for directional lights attenuation will be 1
	half quadFalloff = distanceAttenuation.x;
	half denom = distanceSqr * quadFalloff + 1.0h;
	half lightAtten = 1.0h / denom;

	// We need to smoothly fade attenuation to light range. We start fading linearly at 80% of light range
	// Therefore:
	// fadeDistance = (0.8 * 0.8 * lightRangeSq)
	// smoothFactor = (lightRangeSqr - distanceSqr) / (lightRangeSqr - fadeDistance)
	// We can rewrite that to fit a MAD by doing
	// distanceSqr * (1.0 / (fadeDistanceSqr - lightRangeSqr)) + (-lightRangeSqr / (fadeDistanceSqr - lightRangeSqr)
	// distanceSqr *        distanceAttenuation.y            +             distanceAttenuation.z
	half smoothFactor = saturate(distanceSqr * distanceAttenuation.y + distanceAttenuation.z);
	return lightAtten * smoothFactor;
}

UnityLight ToUnityLight(DeepLight light, half3 normalWorld)
{
	UnityLight unityLight;
	unityLight.color = light.color;
	unityLight.dir = light.dir;
	unityLight.ndotl = saturate(dot(normalWorld, light.dir));
	return unityLight;
}

half3 EvaluatePunctualLight(FragmentCommonData s, DeepLight light, int lightIndex, ShadowContext shadowContext, half3 translucency)
{
	UnityIndirect noIndirect = ZeroIndirect();
	int shadowIndex = _LightShadowIndices[lightIndex];
	half atten = 1.0;

	half3 tolight = light.dir.xyz - s.posWorld;
	half3 lightDir = normalize(tolight);
	atten = DistanceAttenuation(dot(tolight, tolight), light.distanceAttenuation.xyz);

	half4 spotDir = _LightSpotDir[lightIndex];

	if (spotDir.w != 0.0)
	{
		half SdotL = dot(spotDir.xyz, lightDir);
		half atten1 = saturate(SdotL * spotDir.w + light.distanceAttenuation.w);
		atten *= atten1 * atten1;
	}

	UNITY_BRANCH if (shadowIndex >= 0)
	{
		atten *= GetPunctualShadowAttenuation(shadowContext, s.posWorld, s.normalWorld, shadowIndex, lightDir, length(tolight));
	}

	light.dir = lightDir;

	light.color *= atten;

	return UNITY_BRDF_PBS(s.diffColor, s.specColor, s.oneMinusReflectivity, s.smoothness, s.normalWorld, -s.eyeVec, ToUnityLight(light, s.normalWorld), noIndirect).rgb
#if defined(_TRANSLUCENCY)
        + UNITY_BRDF_PBS(s.diffColor, 0, s.oneMinusReflectivity, s.smoothness, s.normalWorld, -s.eyeVec, ToUnityLight(light, -s.normalWorld), noIndirect).rgb * translucency
#endif
        ;
}

half3 EvaluateDirectionalLight(FragmentCommonData s, DeepLight light, int lightIndex, ShadowContext shadowContext, half3 translucency)
{
	UnityIndirect noIndirect = ZeroIndirect();
	int shadowIndex = _LightShadowIndices[lightIndex];
	half atten = 1.0;

	UNITY_BRANCH if (shadowIndex >= 0)
	{
		atten = GetDirectionalShadowAttenuation(shadowContext, s.posWorld, s.normalWorld, shadowIndex, light.dir.xyz, length(light.dir.xyz));
	}

	light.color *= atten;

	return UNITY_BRDF_PBS(s.diffColor, s.specColor, s.oneMinusReflectivity, s.smoothness, s.normalWorld, -s.eyeVec, ToUnityLight(light, s.normalWorld), noIndirect).rgb
#if defined(_TRANSLUCENCY)
        + UNITY_BRDF_PBS(s.diffColor, 0, s.oneMinusReflectivity, s.smoothness, -s.normalWorld, -s.eyeVec, ToUnityLight(light, -s.normalWorld), noIndirect).rgb * translucency
#endif
        ;
}

half GetPixelLightCount()
{
	//return min(_LightCount.x - unity_LightData.x, unity_LightData.y);
	return unity_LightData.y;
}

void fragBlank (out half4 outColor : SV_Target0, VertexOutputForwardBase i)
{
    outColor = 0;
}

void fragForwardBaseSRP (out half4 outColor : SV_Target0,
    out half4 outFog : SV_Target1, VertexOutputForwardBase i
#if defined(_TREE_MANUFACTURE)
    ,half side : VFACE
#endif
    )
{
// EDITS START
	DISSOLVE_MASK(i.tex.zw);
// EDITS END

    UNITY_APPLY_DITHER_CROSSFADE(i.pos.xy);
    ApplySnowEffectsPre(i.tangentToWorldAndPackedData[2].xyz);

    FRAGMENT_SETUP(s)

    UNITY_SETUP_INSTANCE_ID(i);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

#if defined(_TREE_MANUFACTURE)
    if(side < 0.0)
        s.normalWorld = -s.normalWorld;

    clip(s.alpha - 0.05);
    s.alpha = 1.0;
#endif

    half3 translucency = 0.0;
    half occlusion = Occlusion(i.tex.xy);

    ApplyTreeEffects(s, i.ambientOrLightmapUV.w, translucency, occlusion, i.tex.xy);
    ApplySnowEffects(s, occlusion, i.tex.xy);

	half4 c = 0.0;

	ShadowContext shadowContext = InitShadowContext();

	// directional lights count
	for (int lightIndex = 0; lightIndex < _DirectionalLightsCount; ++lightIndex)
	{
		DeepLight light = GetLight(lightIndex);
		c.rgb += EvaluateDirectionalLight(s, light, lightIndex, shadowContext, translucency);
	}

	// point lights count
	int pixelLightCount = GetPixelLightCount();
	for (int lightIndex2 = 0; lightIndex2 < pixelLightCount; ++lightIndex2)
	{
		int realLightIndex = _LightIndexBuffer[unity_LightData.x + lightIndex2];

		DeepLight light = GetLight(realLightIndex);
		c.rgb += EvaluatePunctualLight(s, light, realLightIndex, shadowContext, translucency);
	}

    UnityLight mainLight = DummyLight ();
	half atten = 1;

    UnityGI gi = FragmentGI (s, occlusion, i.ambientOrLightmapUV, atten, mainLight);

    c += UNITY_BRDF_PBS (s.diffColor, s.specColor, s.oneMinusReflectivity, s.smoothness, s.normalWorld, -s.eyeVec, gi.light, gi.indirect);
    c.rgb += Emission(i.tex.xy);

#if defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2)
	float dist = LinearEyeDepth(i.screenPos.z / i.screenPos.w);

#if defined(_ALPHAPREMULTIPLY_ON)
	DEEP_APPLY_FOG_COLOR(i.fogCoord, c.rgb, _TransparencyFogColor * s.alpha);
#else
    DEEP_APPLY_FOG_COLOR(i.fogCoord, c.rgb, _TransparencyFogColor);
#endif

	half4 volumetricLighting = tex2Dproj(_VolumetricLightingTex, i.screenPos) * _VolumetricIntensity;
	half4 volumetricResult = half4(_TransparencyFogColor.rgb * volumetricLighting.rgb, volumetricLighting.a);
	c.rgb = lerp(c.rgb, c.rgb + volumetricResult.rgb, volumetricResult.a);

	half underwaterMask = tex2Dproj(_UnderwaterMask, i.screenPos);
	c.a = s.alpha;
	c = lerp(c, 0.0, underwaterMask * (1.0 - exp(dist * float4(-0.2262118, -0.0260612, -0.0117647, -0.0117647))));
	s.alpha = c.a;

	outFog = half4(1.0 - unityFogFactor.xxx, s.alpha);
#else
	outFog = half4(0.0, 0.0, 0.0, s.alpha);
#endif

	outColor = OutputForward (c, s.alpha);
}
// SRP END ----

// ------------------------------------------------------------------
//  Additive forward pass (one light per pass)

struct VertexOutputForwardAdd
{
    UNITY_POSITION(pos);
    float4 tex                          : TEXCOORD0;
    float3 eyeVec                       : TEXCOORD1;
    float4 tangentToWorldAndLightDir[3] : TEXCOORD2;    // [3x3:tangentToWorld | 1x3:lightDir]
    float3 posWorld                     : TEXCOORD5;
#if !defined (UNITY_HALF_PRECISION_FRAGMENT_SHADER_REGISTERS)
    UNITY_SHADOW_COORDS(6)
    UNITY_FOG_COORDS(7)
#else
    UNITY_LIGHTING_COORDS(6, 7)
    UNITY_FOG_COORDS(8)
#endif

    // next ones would not fit into SM2.0 limits, but they are always for SM3.0+
#if defined(_PARALLAXMAP)
    half3 viewDirForParallax            : TEXCOORD8;
#endif

    UNITY_VERTEX_OUTPUT_STEREO
};

// ------------------------------------------------------------------
//  Deferred pass

struct VertexOutputDeferred
{
    UNITY_POSITION(pos);
    float4 tex                            : TEXCOORD0;
    float3 eyeVec                         : TEXCOORD1;
    float4 tangentToWorldAndPackedData[3] : TEXCOORD2;    // [3x3:tangentToWorld | 1x3:viewDirForParallax or worldPos]
    half4 ambientOrLightmapUV             : TEXCOORD5;    // SH or Lightmap UVs

    #if UNITY_REQUIRE_FRAG_WORLDPOS && !UNITY_PACK_WORLDPOS_WITH_TANGENT
        float3 posWorld                     : TEXCOORD6;
    #endif

	#if defined(_DAMAGE_MAP) || defined(_WETNESS_SUPPORT_ON)
		half2 damageMapUV					: TEXCOORD7;
	#endif

    #if defined(IMPOSTOR_BAKE)
        float depth                         : TEXCOORD8;
    #endif

    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

VertexOutputDeferred vertDeferred (VertexInput v)
{
    UNITY_SETUP_INSTANCE_ID(v);
    VertexOutputDeferred o;
    UNITY_INITIALIZE_OUTPUT(VertexOutputDeferred, o);
    UNITY_TRANSFER_INSTANCE_ID(v, o);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

#if defined(_FLAG)
	float frameIndex = (_Time.y * _FlagAnimationSpeed) % _FlagAnimationFrameCount;
	int frameIndexLB = floor(frameIndex);
	int frameIndexUB = ceil(frameIndex);

	if(frameIndexUB == _FlagAnimationFrameCount)
		frameIndexUB = 0;

	float lerpFactor = frameIndex - frameIndexLB;
	int vertexID = v.id;

	int vbIndexLB = frameIndexLB * _FlagAnimationVertexCount + vertexID;
	int vbIndexUB = frameIndexUB * _FlagAnimationVertexCount + vertexID;

	v.vertex.xyz = lerp(_FlagAnimation[vbIndexLB].Position.xyz, _FlagAnimation[vbIndexUB].Position.xyz, lerpFactor);
	v.normal.xyz = lerp(_FlagAnimation[vbIndexLB].Normal.xyz, _FlagAnimation[vbIndexUB].Normal.xyz, lerpFactor);

#if defined(_TANGENT_TO_WORLD)
	v.tangent.xyz = lerp(_FlagAnimation[vbIndexLB].Tangent.xyz, _FlagAnimation[vbIndexUB].Tangent.xyz, lerpFactor);
#endif
#endif

#if defined(_BILLBOARD)
    AFSBillboardVert_DWS(/*inout*/ v);
#endif

#if defined(_SIMPLE_WATER)
	v.vertex.xz = lerp(v.uv2, v.vertex.xz, _FillRatio);
#endif

#if defined(DECAL)
    v.vertex.xyz += v.normal * 0.001;
#endif

#if defined(_TREE_LEAVES)
    float3 pivot;

	// 15bit compression 2 components only, important: sign of y
	pivot.xz = (frac(float2(1.0f, 32768.0f) * v.uv2.xx) * 2) - 1;
	pivot.y = sqrt(1 - saturate(dot(pivot.xz, pivot.xz)));
	pivot *= v.uv2.y;
	#if !defined(IS_LODTREE)
		pivot *= _TreeInstanceScale.xyz;
	#endif

	float4 TerrainLODWind = _TerrainLODWind;
	TerrainLODWind.xyz = mul((float3x3)unity_WorldToObject, _TerrainLODWind.xyz);
	CTI_AnimateVertex_DWS( v, float4(v.vertex.xyz, v.color.b), v.normal, float4(v.color.xy, v.uv1.xy), pivot, v.color.b, TerrainLODWind, v.uv2.z);
#elif defined(_TREE_BARK)
    float4 TerrainLODWind = _TerrainLODWind;
	TerrainLODWind.xyz = mul((float3x3)unity_WorldToObject, _TerrainLODWind.xyz);
	CTI_AnimateVertex_DWS( v, float4(v.vertex.xyz, v.color.b), v.normal, float4(v.color.xy, v.uv1.xy), float3(0,0,0), 0, TerrainLODWind, 0); //v.uv2.z);
#elif defined(_TREE_LEAVES_MANUFACTURE) || defined(_TREE_BARK_MANUFACTURE)
    CalculateWind(v);
#endif

    float4 posWorld = mul(unity_ObjectToWorld, v.vertex);

#if defined(USE_CUSTOM_AMBIENT) && !defined(_BILLBOARD)			// apply earth curvature effect only to exterior meshes
	posWorld = CompensateForEarthCurvature(posWorld);
#endif

#if defined(_SIMPLE_WATER)
	v.vertex.y -= max(0.0, posWorld.y - _ClipHeight);
	posWorld.y = min(posWorld.y, _ClipHeight);
#endif

    #if UNITY_REQUIRE_FRAG_WORLDPOS
        #if UNITY_PACK_WORLDPOS_WITH_TANGENT
            o.tangentToWorldAndPackedData[0].w = posWorld.x;
            o.tangentToWorldAndPackedData[1].w = posWorld.y;
            o.tangentToWorldAndPackedData[2].w = posWorld.z;
        #else
            o.posWorld = posWorld.xyz;
        #endif
    #endif

	float3 normalWorld = UnityObjectToWorldNormal(v.normal);

#if defined(_HAIR)
	posWorld.xyz += normalWorld * _HairOffset;
#endif

    o.pos = mul(UNITY_MATRIX_VP, posWorld);

#if defined(_BILLBOARD)
    o.pos = UnityObjectToClipPos(v.vertex);
#endif

    o.tex = TexCoords(v);
    o.eyeVec = NormalizePerVertexNormal(posWorld.xyz - _WorldSpaceCameraPos);
    #ifdef _TANGENT_TO_WORLD
        float4 tangentWorld = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);

        float3x3 tangentToWorld = CreateTangentToWorldPerVertex(normalWorld, tangentWorld.xyz, tangentWorld.w);
        o.tangentToWorldAndPackedData[0].xyz = tangentToWorld[0];
        o.tangentToWorldAndPackedData[1].xyz = tangentToWorld[1];
        o.tangentToWorldAndPackedData[2].xyz = tangentToWorld[2];
    #else
        o.tangentToWorldAndPackedData[0].xyz = 0;
        o.tangentToWorldAndPackedData[1].xyz = 0;
        o.tangentToWorldAndPackedData[2].xyz = normalWorld;
    #endif

    o.ambientOrLightmapUV = 0;
    #ifdef LIGHTMAP_ON
        o.ambientOrLightmapUV.xy = v.uv1.xy * unity_LightmapST.xy + unity_LightmapST.zw;
    #elif UNITY_SHOULD_SAMPLE_SH
        o.ambientOrLightmapUV.rgb = ShadeSHPerVertex (normalWorld, o.ambientOrLightmapUV.rgb);
    #endif
    #if defined(DYNAMICLIGHTMAP_ON)
        o.ambientOrLightmapUV.zw = v.uv2.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
    #endif

#if defined(_BILLBOARD)
    o.ambientOrLightmapUV.w = v.color.r;
#elif defined(_TREE_LEAVES_MANUFACTURE)
    float hueVariationAmount = frac(dot(unity_ObjectToWorld._m03_m13_m23, 1));
	o.ambientOrLightmapUV.w = saturate(hueVariationAmount * lerp(_HueVariation.a, _HueVariationAutumn.a, _SeasonBlendFactor));
#endif

	#if defined(_DAMAGE_MAP) || defined(_WETNESS_SUPPORT_ON)
		o.damageMapUV.xy = _UVWetnessMap == 0 ? o.tex.xy : v.uv1.xy;
	#endif

    #ifdef _PARALLAXMAP
        TANGENT_SPACE_ROTATION;
        half3 viewDirForParallax = mul (rotation, ObjSpaceViewDir(v.vertex));
        o.tangentToWorldAndPackedData[0].w = viewDirForParallax.x;
        o.tangentToWorldAndPackedData[1].w = viewDirForParallax.y;
        o.tangentToWorldAndPackedData[2].w = viewDirForParallax.z;
    #endif

    #ifdef USE_CUSTOM_AMBIENT
        float finalDepth = o.pos.z / abs(o.pos.w);

	    if(finalDepth < _FarRenderingParams.x)
	    {
		    float correctedDepth = finalDepth * _FarRenderingParams.z + _FarRenderingParams.y;
		    o.pos.z = correctedDepth * abs(o.pos.w);
	    }
    #endif

    #if defined(IMPOSTOR_BAKE)
        o.depth = -UnityObjectToViewPos(v.vertex.xyz).z;
    #endif

    return o;
}

void fragDeferred (
    VertexOutputDeferred i,
    out half4 outGBuffer0 : SV_Target0,
    out half4 outGBuffer1 : SV_Target1,
    out half4 outGBuffer2 : SV_Target2,
    out half4 outEmission : SV_Target3          // RT3: emission (rgb), --unused-- (a)
#if defined(DECAL_FULL)
    ,out half4 outDecal : SV_Target4
#endif
#if defined(_TREE_MANUFACTURE) || defined(_FLAG)
    ,half side : VFACE
#endif
)
{
    #if (SHADER_TARGET < 30)
        outGBuffer0 = 1;
        outGBuffer1 = 1;
        outGBuffer2 = 0;
        outEmission = 0;
        #if defined(DECAL_FULL)
            outDecal = 0;
        #endif
        return;
    #endif

	// EDITS START
	DISSOLVE_MASK(i.tex.zw);
	// EDITS END

    UNITY_APPLY_DITHER_CROSSFADE(i.pos.xy);
    half wetness = ApplyWetnessPre(i.damageMapUV.xy);
    ApplySnowEffectsPre(i.tangentToWorldAndPackedData[2].xyz);

    float2 unparallaxedUV = i.tex.zw;

    FRAGMENT_SETUP(s)
    UNITY_SETUP_INSTANCE_ID(i);

#if defined(_TREE_MANUFACTURE) || defined(_FLAG)
    if(side < 0.0)
        s.normalWorld = -s.normalWorld;
#endif

	ApplyDamage(i.tex.xy, i.damageMapUV.xy, s);
	ApplyWetness(i.damageMapUV.xy, wetness, s);
    half3 translucency = 0.0;
    half occlusion = Occlusion(i.tex.xy);
    ApplyTreeEffects(s, i.ambientOrLightmapUV.w, translucency, occlusion, i.tex.xy);
    ApplyMegatex(s, occlusion, float4(i.tex.xy, lerp(i.tex.zw, unparallaxedUV, 0.65)), IN_WORLDPOS(i));
    ApplySnowEffects(s, occlusion, i.tex.xy);

    // no analytic lights in this pass
    UnityLight dummyLight = DummyLight ();
    half atten = 1;

    // only GI
#if UNITY_ENABLE_REFLECTION_BUFFERS
    bool sampleReflectionsInDeferred = false;
#else
    bool sampleReflectionsInDeferred = true;
#endif

    UnityGI gi = FragmentGI (s, occlusion, i.ambientOrLightmapUV, atten, dummyLight, sampleReflectionsInDeferred);

    half3 emissiveColor = UNITY_BRDF_PBS (s.diffColor, s.specColor, s.oneMinusReflectivity, s.smoothness, s.normalWorld, -s.eyeVec, gi.light, gi.indirect).rgb;

    #ifdef _EMISSION
        half3 emission = Emission (i.tex.xy);
		ApplyLighthouseEffect(emission, i.tex.zw);
		emissiveColor += emission;
    #endif

    #ifndef UNITY_HDR_ON
        emissiveColor.rgb = exp2(-emissiveColor.rgb);
    #endif

    UnityStandardData data;
    data.diffuseColor   = s.diffColor;
    data.occlusion      = occlusion;
    data.specularColor  = s.specColor;
    data.smoothness     = s.smoothness;
    data.normalWorld    = s.normalWorld;

    UnityStandardDataToGbuffer(data, outGBuffer0, outGBuffer1, outGBuffer2);

    // Emissive lighting buffer
    outEmission = half4(emissiveColor, _SubsurfaceScatteringIntensity);

#if defined(_SUBSURFACE_SCATTERING_NORMALMAP)
    outEmission.a = tex2D(_BumpMap, i.tex.xy).b;
#endif

#if defined(DECAL_FULL)
    outDecal = half4(outGBuffer1.a, s.alpha * _PerChannelAlpha.y, 1.0, 1.0);
    outGBuffer0.a = s.alpha * _PerChannelAlpha.x;
    outGBuffer1.a = s.alpha * _PerChannelAlpha.y;
    outGBuffer2.a = s.alpha * _PerChannelAlpha.z;
    outEmission.a = s.alpha * _PerChannelAlpha.w;
#elif defined(DECAL)
    #if defined(_ALPHATEST_ON)
        outGBuffer2.a = (s.alpha - _Cutoff) / (1.0 - _Cutoff);
    #else
        outGBuffer2.a = s.alpha;
    #endif
#endif

#if defined(HAIR)
    outGBuffer0.a = s.alpha;
    outGBuffer2.a = s.alpha;
    outEmission.a = s.alpha;
#endif

#if defined(IMPOSTOR_BAKE)
    outGBuffer0.a = s.alpha;

    float depth_temp = ( -1.0 / UNITY_MATRIX_P[2].z );
    outGBuffer2.a = (i.depth + depth_temp) / depth_temp;

#if defined(_SNOW_SUPPORT_ON)
    outEmission.g = saturate((i.tangentToWorldAndPackedData[2].y - 0.5) * 8.0);         // snow factor
#else
    outEmission.g = 0.0;
#endif

    outEmission.a = occlusion;
#endif
}


//
// Old FragmentGI signature. Kept only for backward compatibility and will be removed soon
//

inline UnityGI FragmentGI(
    float3 posWorld,
    half occlusion, half4 i_ambientOrLightmapUV, half atten, half smoothness, half3 normalWorld, half3 eyeVec,
    UnityLight light,
    bool reflections)
{
    // we init only fields actually used
    FragmentCommonData s = (FragmentCommonData)0;
    s.smoothness = smoothness;
    s.normalWorld = normalWorld;
    s.eyeVec = eyeVec;
    s.posWorld = posWorld;
    return FragmentGI(s, occlusion, i_ambientOrLightmapUV, atten, light, reflections);
}
inline UnityGI FragmentGI (
    float3 posWorld,
    half occlusion, half4 i_ambientOrLightmapUV, half atten, half smoothness, half3 normalWorld, half3 eyeVec,
    UnityLight light)
{
    return FragmentGI (posWorld, occlusion, i_ambientOrLightmapUV, atten, smoothness, normalWorld, eyeVec, light, true);
}

#if defined(TESSELATION)

#include "Tessellation.cginc"

float _TesselationFactor;

struct UnityTessellationFactors {
	float edge[4]  : SV_TessFactor;
	float inside[2] : SV_InsideTessFactor;
};

[UNITY_domain("quad")]
[UNITY_partitioning("integer")]
[UNITY_outputtopology("triangle_cw")]
[UNITY_patchconstantfunc("hsconst")]
[UNITY_outputcontrolpoints(4)]
TesselatorVertexInput hs_surf(InputPatch<TesselatorVertexInput, 4> v, uint id : SV_OutputControlPointID)
{
	return v[id];
}

UnityTessellationFactors hsconst(InputPatch<TesselatorVertexInput, 4> v)
{
	UnityTessellationFactors o;

	float4 tess = float4(v[0].tessFactor, v[1].tessFactor, v[2].tessFactor, v[3].tessFactor);
	o.edge[0] = 0.5 * (tess.x + tess.w);
	o.edge[1] = 0.5 * (tess.x + tess.y);
	o.edge[2] = 0.5 * (tess.y + tess.z);
	o.edge[3] = 0.5 * (tess.z + tess.w);
	o.inside[0] = o.inside[1] = (o.edge[0] + o.edge[1] + o.edge[2] + o.edge[3]) * 0.25;

	return o;
}

#define DOMAIN_INTERPOLATE(fieldName) v.fieldName = lerp(\
		lerp(patch[0].fieldName, patch[1].fieldName, UV.x), \
		lerp(patch[3].fieldName, patch[2].fieldName, UV.x), \
		UV.y)

float3 pt_pi(float3 q, float3 p, float3 n)
{
    return q + dot(q - p, n) * n;
}

[UNITY_domain("quad")]
TESS_OUTPUT ds_surf (UnityTessellationFactors tessFactors, const OutputPatch<TesselatorVertexInput, 4> patch, float2 UV : SV_DomainLocation)
{
	VertexInput v;

    DOMAIN_INTERPOLATE(vertex);
    DOMAIN_INTERPOLATE(normal);
    DOMAIN_INTERPOLATE(uv0);
    DOMAIN_INTERPOLATE(uv1);

#if defined(_TREE) || defined(_BILLBOARD)

    DOMAIN_INTERPOLATE(color);
    DOMAIN_INTERPOLATE(uv2);

#elif defined(DYNAMICLIGHTMAP_ON) || defined(UNITY_PASS_META) || defined(_DAMAGE_MAP) || defined(_SIMPLE_WATER)
    
    DOMAIN_INTERPOLATE(uv2);

#endif

#ifdef _TANGENT_TO_WORLD
    DOMAIN_INTERPOLATE(tangent);
#endif

#if defined(UNITY_INSTANCING_ENABLED) || defined(UNITY_PROCEDURAL_INSTANCING_ENABLED) || defined(UNITY_STEREO_INSTANCING_ENABLED)
    v.instanceID = patch[0].instanceID;
#endif

    v.vertex.xyz = (1.0 - UV.x) * (1.0 - UV.y) * pt_pi(v.vertex.xyz, patch[0].vertex.xyz, patch[0].normal)
        + UV.x * (1.0 - UV.y) * pt_pi(v.vertex.xyz, patch[1].vertex.xyz, patch[1].normal)
        + (1.0 - UV.x) * UV.y * pt_pi(v.vertex.xyz, patch[3].vertex.xyz, patch[3].normal)
        + UV.x * UV.y * pt_pi(v.vertex.xyz, patch[2].vertex.xyz, patch[2].normal);

	TESS_OUTPUT o = POST_TESS_VERT (v);
	return o;
}

TesselatorVertexInput tessvert_surf (VertexInput v)
{
	TesselatorVertexInput o;
	o.vertex = v.vertex;
	o.tessFactor = UnityCalcDistanceTessFactor(o.vertex, _ProjectionParams.y, _ProjectionParams.z, _TesselationFactor);
    o.normal = v.normal;
    o.uv0 = v.uv0;
    o.uv1 = v.uv1;
#if defined(_TREE) || defined(_BILLBOARD)
    o.color = v.color;
    o.uv2 = v.uv2;
#elif defined(DYNAMICLIGHTMAP_ON) || defined(UNITY_PASS_META) || defined(_DAMAGE_MAP) || defined(_SIMPLE_WATER)
    o.uv2 = v.uv2;
#endif
#ifdef _TANGENT_TO_WORLD
    o.tangent = v.tangent;
#endif
	return o;
}
#endif

#endif // UNITY_STANDARD_CORE_INCLUDED
