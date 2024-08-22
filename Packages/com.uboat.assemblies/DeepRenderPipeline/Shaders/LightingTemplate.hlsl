#ifndef __DEFERREDLIGHTINGTEMPLATE_H__
#define __DEFERREDLIGHTINGTEMPLATE_H__


#include "UnityCG.cginc"
#include "UnityStandardBRDF.cginc"
#include "UnityStandardUtils.cginc"
#include "UnityPBSLighting.cginc"

//uniform uint g_nNumDirLights;

//---------------------------------------------------------------------------------------------------------------------------------------------------------
// TODO:  clean up.. -va
#define MAX_SHADOW_LIGHTS 10
#define MAX_SHADOWMAP_PER_LIGHT 6
#define MAX_DIRECTIONAL_SPLIT  4

#define CUBEMAPFACE_POSITIVE_X 0
#define CUBEMAPFACE_NEGATIVE_X 1
#define CUBEMAPFACE_POSITIVE_Y 2
#define CUBEMAPFACE_NEGATIVE_Y 3
#define CUBEMAPFACE_POSITIVE_Z 4
#define CUBEMAPFACE_NEGATIVE_Z 5

#define SHADOW_USE_VIEW_BIAS_SCALING            1   // Enable view bias scaling to mitigate light leaking across edges. Uses the light vector if SHADOW_USE_ONLY_VIEW_BASED_BIASING is defined, otherwise uses the normal.
// Note: Sample biasing work well but is very costly in term of VGPR, disable it for now
#define SHADOW_USE_SAMPLE_BIASING               0   // Enable per sample biasing for wide multi-tap PCF filters. Incompatible with SHADOW_USE_ONLY_VIEW_BASED_BIASING.
#define SHADOW_USE_DEPTH_BIAS                   0   // Enable clip space z biasing

sampler2D _CameraGBufferTexture0;
sampler2D _CameraGBufferTexture1;
sampler2D _CameraGBufferTexture2;

sampler2D _CausticsMap;
sampler2D _CausticsDistortionMap;
sampler2D _UnderwaterMask;
sampler2D _WaterlessDepthTexture;
sampler2D _WaterDepthTexture;
float	  _CausticsMapKey;
float	  _CausticsMultiplier;
float4x4  _CausticsMapProj;
float4	  _CausticsParams;
float4	  _CausticsOffset;
float4	  _CausticsFrameCoords;
half4	  _AbsorptionColor;
half4	  _CausticsSurfaceColor;
sampler2D _TotalDisplacementMap;
float4	  _LocalMapsCoords;
float	  _LightIndexForShadowMatrixArray;
float	  _ContactShadowMask;
half	  _MaxSmoothness;

sampler2D _AmbientOcclusionTexture;
half4	  _AmbientOcclusionParam;

#if defined(SHADER_API_D3D11)
#	include "Packages/com.unity.render-pipelines.core/ShaderLibrary/API/D3D11.hlsl"
#elif defined(SHADER_API_PSSL)
#	include "Packages/com.unity.render-pipelines.core/ShaderLibrary/API/PSSL.hlsl"
#elif defined(SHADER_API_XBOXONE)
#	include "Packages/com.unity.render-pipelines.core/ShaderLibrary/API/D3D11.hlsl"
#	include "Packages/com.unity.render-pipelines.core/ShaderLibrary/API/D3D11_1.hlsl"
#elif defined(SHADER_API_METAL)
#	include "Packages/com.unity.render-pipelines.core/ShaderLibrary/API/Metal.hlsl"
#else
#	error unsupported shader api
#endif
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/API/Validate.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "ShadowDispatch.hlsl"

#if UNITY_VERSION >= 550
	#define conditionalTex2D tex2D
#else
	#define conditionalTex2D tex2Dlod
#endif

Texture2D<uint> _ContactShadowTexture;

// In the first 8 bits of the target we store the max fade of the contact shadows as a byte
void UnpackContactShadowData(uint contactShadowData, out float fade, out uint mask)
{
    fade = float(contactShadowData >> 24) / 255.0;
    mask = contactShadowData & 0xFFFFFF; // store only the first 24 bits which represent 
}

void InitContactShadow(uint3 positionSS, out float contactShadowFade, out uint contactShadowMask)
{
    // Note: When we ImageLoad outside of texture size, the value returned by Load is 0 (Note: On Metal maybe it clamp to value of texture which is also fine)
    // We use this property to have a neutral value for contact shadows that doesn't consume a sampler and work also with compute shader (i.e use ImageLoad)
    // We store inverse contact shadow so neutral is white. So either we sample inside or outside the texture it return 1 in case of neutral
    uint packedContactShadow = _ContactShadowTexture.Load(positionSS).x;
    UnpackContactShadowData(packedContactShadow, contactShadowFade, contactShadowMask);
}

float GetContactShadow(int contactShadowMask, float contactShadowFade1, uint contactShadowMask1)
{
	float _ContactShadowOpacity = 0.83f;
	
    bool occluded = (contactShadowMask1 & contactShadowMask) != 0;
    return 1.0 - occluded * contactShadowFade1 * _ContactShadowOpacity;
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

float3 ApplyWaterInfluence(float2 uv, float3 wpos, float3 normalWorld)
{
#if defined(WATER_BUFFERS_ENABLED) && (defined(DIRECTIONAL) || defined (DIRECTIONAL_COOKIE))
	//UNITY_BRANCH
	//if(abs(_LightPos.y - 6.137) < 0.001)
	//{
		// apply directional light caustics
		float4 uvlod = float4(uv, 0.0, 0.0);
		float waterDepth = tex2Dlod(_WaterDepthTexture, uvlod).r;
		float depth = tex2Dlod(_WaterlessDepthTexture, uvlod).r;
		half underwaterMask = tex2Dlod(_UnderwaterMask, uvlod).r;

#if UNITY_VERSION >= 550
		waterDepth = lerp(waterDepth, 1.0, underwaterMask);
		//if (waterDepth > depth)
#else
		waterDepth *= 1.0 - underwaterMask;
		//if(waterDepth < depth)
#endif
		{
			float2 uvx = mul(_CausticsMapProj, float4(wpos, 1)).xy;
			uvx.xy = uvx.xy * float2(0.5, -0.5) + 0.5;

			half2 distort = tex2D(_CausticsDistortionMap, uvx);

			float4 uvx2 = uvx.xyxy;
			uvx2 += distort.xyyx * _CausticsParams.xxyy;
			uvx2 = uvx2 * _CausticsParams.z + _CausticsOffset;
			uvx2 = (uvx2-floor(uvx2)) * 0.166666666;

			half caustic1 = tex2D(_CausticsMap, uvx2.xy + _CausticsFrameCoords.xy).r;
			half caustic2 = tex2D(_CausticsMap, uvx2.xy + _CausticsFrameCoords.zw).r;

			caustic1 += tex2D(_CausticsMap, uvx2.zw + _CausticsFrameCoords.xy).r;
			caustic2 += tex2D(_CausticsMap, uvx2.zw + _CausticsFrameCoords.zw).r;

			half caustic = lerp(caustic1, caustic2, _CausticsParams.w);

			half2 localUv = uv * _LocalMapsCoords.zz + _LocalMapsCoords.xy;
			half waterElevation = tex2Dlod(_TotalDisplacementMap, half4(localUv, 0, 0)).y;
			half elevationDelta = wpos.y - waterElevation;

			UNITY_BRANCH
			if (waterDepth > depth)
			{
				half depthDelta = LinearEyeDepth(depth) - LinearEyeDepth(waterDepth);
				return lerp(1, caustic * _CausticsMultiplier * exp(_AbsorptionColor * 0.2 * (min(elevationDelta, 0.0) - abs(depthDelta))), min(1.0, 5.0 * depthDelta));
			}
			else
			{
				return 1.0 + caustic * _CausticsSurfaceColor * max(0.0, 0.65 - normalWorld.y) / max(1.0, elevationDelta + 1.0);
			}
		}
	/*}
	else
	{
		// apply light fade under water
		float4 uvlod = float4(uv, 0.0, 0.0);
		float waterDepth = tex2Dlod(_WaterDepthTexture, uvlod).r;
		float depth = tex2Dlod(_WaterlessDepthTexture, uvlod).r;
		half underwaterMask = tex2Dlod(_UnderwaterMask, uvlod).r;

#if UNITY_VERSION >= 550
		waterDepth = lerp(waterDepth, 1.0, underwaterMask);
		if (waterDepth > depth)
#else
		waterDepth *= 1.0 - underwaterMask;
		if (waterDepth < depth)
#endif
		{
			half2 localUv = uv * _LocalMapsCoords.zz + _LocalMapsCoords.xy;
			half waterElevation = tex2Dlod(_TotalDisplacementMap, half4(localUv, 0, 0)).y;

			half depthDelta = LinearEyeDepth(depth) - LinearEyeDepth(waterDepth);

			return lerp(1, _CausticsMultiplier * exp(_AbsorptionColor * 0.15 * (min(wpos.y - waterElevation, 0.0) - abs(depthDelta))), min(1.0, 5.0 * depthDelta));
		}
	}*/
#endif

	return 1;
}

half4 CalculateLight (unity_v2f_deferred i)
{
	float3 wpos;
	float2 uv;
	float atten, fadeDist;
	UnityLight light;
	UNITY_INITIALIZE_OUTPUT(UnityLight, light);
	UnityDeferredCalculateLightParams (i, wpos, uv, light.dir, atten, fadeDist);

	// unpack Gbuffer
	half4 gbuffer0 = tex2D (_CameraGBufferTexture0, uv);
	half4 gbuffer1 = tex2D (_CameraGBufferTexture1, uv);
	half4 gbuffer2 = tex2D (_CameraGBufferTexture2, uv);

	UnityStandardData data = UnityStandardDataFromGbuffer(gbuffer0, gbuffer1, gbuffer2);
	data.smoothness = GeometricNormalFiltering(data.smoothness, data.normalWorld, 0.235, 0.53);
	data.smoothness = min(data.smoothness, _MaxSmoothness);

	ShadowContext shadowContext = InitShadowContext();

	float3 tolight = _LightPos.xyz - wpos;
	half3 lightDir = normalize(tolight);

	float contactShadowFade;
	uint contactShadowMask;
	InitContactShadow(uint3(uv.x * _ScreenParams.x, uv.y * _ScreenParams.y, 0), contactShadowFade, contactShadowMask);

	if (_LightIndexForShadowMatrixArray >= 0)
#if defined (CYLINDRICAL_LIGHT)
		atten *= 1.0;
#elif defined (POINT) || defined (POINT_COOKIE)
		atten *= GetPunctualShadowAttenuation(shadowContext, wpos, data.normalWorld, _LightIndexForShadowMatrixArray, lightDir, length(tolight));
#elif defined(SPOT) || defined (SPOT_COOKIE)
		atten *= GetPunctualShadowAttenuation(shadowContext, wpos, data.normalWorld, _LightIndexForShadowMatrixArray, lightDir, length(tolight));
#elif defined (DIRECTIONAL) || defined(DIRECTIONAL_COOKIE)
		atten *= GetDirectionalShadowAttenuation(shadowContext, wpos, data.normalWorld, _LightIndexForShadowMatrixArray, lightDir, length(tolight));
#endif

	if (_ContactShadowMask > 0)
		atten *= GetContactShadow(_ContactShadowMask, contactShadowFade, contactShadowMask);
	
	float3 atten3 = atten * ApplyWaterInfluence(uv, wpos, data.normalWorld);

	light.color = _LightColor.rgb * atten3;

	float3 eyeDelta = wpos - _WorldSpaceCameraPos;
	float3 eyeVec = normalize(eyeDelta);
	half oneMinusReflectivity = 1 - SpecularStrength(data.specularColor.rgb);

	UnityIndirect ind;
	UNITY_INITIALIZE_OUTPUT(UnityIndirect, ind);
	ind.diffuse = 0;
	ind.specular = 0;

    half4 res = UNITY_BRDF_PBS (data.diffuseColor, data.specularColor, oneMinusReflectivity, data.smoothness, data.normalWorld, -eyeVec, light, ind);

	half occlusion = min(1.0, gbuffer0.a + 0.3);
	res.rgb *= lerp(1, occlusion, min(1.0, dot(eyeDelta, eyeDelta) / 32400) * 0.45);

	half ao = tex2D(_AmbientOcclusionTexture, uv);
	res.rgb *= lerp(1.0, ao, _AmbientOcclusionParam.w) / ao;		// w = direct lighting occlusion

	return res;
}

half4 CalculateLight (UnityLight light, float3 wpos, float atten, float3 diffuseColor, float occlusion, float4 specColor, float3 normalWorld)
{
	UnityStandardData data;

	data.diffuseColor = diffuseColor;
	data.occlusion = occlusion;
	data.specularColor = specColor.rgb;
	data.smoothness = specColor.a;
	data.normalWorld = normalWorld;

	data.smoothness = GeometricNormalFiltering(data.smoothness, data.normalWorld, 0.235, 0.53);

	ShadowContext shadowContext = InitShadowContext();


	float3 tolight = light.dir.xyz - wpos;
	half3 lightDir = normalize(tolight);

	if (_LightIndexForShadowMatrixArray >= 0)
#if defined (CYLINDRICAL_LIGHT)
		atten *= 1.0;
#elif defined (POINT) || defined (POINT_COOKIE)
		atten *= GetPunctualShadowAttenuation(shadowContext, wpos, data.normalWorld, _LightIndexForShadowMatrixArray, lightDir, length(tolight));
#elif defined(SPOT) || defined (SPOT_COOKIE)
		atten *= GetPunctualShadowAttenuation(shadowContext, wpos, data.normalWorld, _LightIndexForShadowMatrixArray, lightDir, length(tolight));
#elif defined (DIRECTIONAL) || defined(DIRECTIONAL_COOKIE)
		atten *= GetDirectionalShadowAttenuation(shadowContext, wpos, data.normalWorld, _LightIndexForShadowMatrixArray, lightDir, length(tolight));
#endif

	float3 atten3 = atten;// *ApplyWaterInfluence(uv, wpos, data.normalWorld);

	light.color = _LightColor.rgb * atten3;

	float3 eyeDelta = wpos - _WorldSpaceCameraPos;
	float3 eyeVec = normalize(eyeDelta);
	half oneMinusReflectivity = 1 - SpecularStrength(data.specularColor.rgb);

	UnityIndirect ind;
	UNITY_INITIALIZE_OUTPUT(UnityIndirect, ind);
	ind.diffuse = 0;
	ind.specular = 0;

    half4 res = UNITY_BRDF_PBS (data.diffuseColor, data.specularColor, oneMinusReflectivity, data.smoothness, data.normalWorld, -eyeVec, light, ind);

	occlusion = max(0.0, occlusion - 0.3);
	res.rgb *= lerp(1, occlusion, min(1.0, dot(eyeDelta, eyeDelta) / 32400) * 0.55);

	//half ao = tex2D(_AmbientOcclusionTexture, uv);
	//res.rgb *= lerp(1.0, ao, _AmbientOcclusionParam.w) / ao;		// w = direct lighting occlusion

	return res;
}

#endif
