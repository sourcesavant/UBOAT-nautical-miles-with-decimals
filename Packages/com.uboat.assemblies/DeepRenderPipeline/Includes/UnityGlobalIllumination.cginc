// Upgrade NOTE: replaced 'UNITY_PASS_TEXCUBE(unity_SpecCube1)' with 'UNITY_PASS_TEXCUBE_SAMPLER(unity_SpecCube1,unity_SpecCube0)'

#ifndef UNITY_GLOBAL_ILLUMINATION_INCLUDED
#define UNITY_GLOBAL_ILLUMINATION_INCLUDED

// Functions sampling light environment data (lightmaps, light probes, reflection probes), which is then returned as the UnityGI struct.


#include "UnityStandardBRDF.cginc"
#include "../Includes/UnityStandardUtils.cginc"
#include "../Includes/WaterLib.cginc"

inline half3 DecodeDirectionalSpecularLightmap (half3 color, fixed4 dirTex, half3 normalWorld, bool isRealtimeLightmap, fixed4 realtimeNormalTex, out UnityLight o_light)
{
	o_light.color = color;
	o_light.dir = dirTex.xyz * 2 - 1;

	// The length of the direction vector is the light's "directionality", i.e. 1 for all light coming from this direction,
	// lower values for more spread out, ambient light.
	half directionality = length(o_light.dir);
	o_light.dir /= directionality;

	#ifdef DYNAMICLIGHTMAP_ON
	if (isRealtimeLightmap)
	{
		// Realtime directional lightmaps' intensity needs to be divided by N.L
		// to get the incoming light intensity. Baked directional lightmaps are already
		// output like that (including the max() to prevent div by zero).
		half3 realtimeNormal = realtimeNormalTex.zyx * 2 - 1;
		o_light.color /= max(0.125, dot(realtimeNormal, o_light.dir));
	}
	#endif

	o_light.ndotl = LambertTerm(normalWorld, o_light.dir);

	// Split light into the directional and ambient parts, according to the directionality factor.
	half3 ambient = o_light.color * (1 - directionality);
	o_light.color = o_light.color * directionality;

	// Technically this is incorrect, but helps hide jagged light edge at the object silhouettes and
	// makes normalmaps show up.
	ambient *= o_light.ndotl;
	return ambient;
}

inline half3 MixLightmapWithRealtimeAttenuation (half3 lightmapContribution, half attenuation, fixed4 bakedColorTex)
{
	// Let's try to make realtime shadows work on a surface, which already contains
	// baked lighting and shadowing from the current light.
	// Generally do min(lightmap,shadow), with "shadow" taking overall lightmap tint into account.
	half3 shadowLightmapColor = bakedColorTex.rgb * attenuation;
	half3 darkerColor = min(lightmapContribution, shadowLightmapColor);

	// However this can darken overbright lightmaps, since "shadow color" will
	// never be overbright. So take a max of that color with attenuated lightmap color.
	return max(darkerColor, lightmapContribution * attenuation);
}

inline void ResetUnityLight(out UnityLight outLight)
{
	outLight.color = 0;
	outLight.dir = 0;
	outLight.ndotl = 0;
}

inline void ResetUnityGI(out UnityGI outGI)
{
	ResetUnityLight(outGI.light);
	#ifdef DIRLIGHTMAP_SEPARATE
		#ifdef LIGHTMAP_ON
			ResetUnityLight(outGI.light2);
		#endif
		#ifdef DYNAMICLIGHTMAP_ON
			ResetUnityLight(outGI.light3);
		#endif
	#endif
	outGI.indirect.diffuse = 0;
	outGI.indirect.specular = 0;
}

inline UnityGI UnityGlobalIllumination (UnityGIInput data, half occlusion, half oneMinusRoughness, half3 normalWorld, bool reflections, half2 dirRoughness)
{
	UnityGI o_gi;
	UNITY_INITIALIZE_OUTPUT(UnityGI, o_gi);

	// Explicitly reset all members of UnityGI
	ResetUnityGI(o_gi);

	#if UNITY_SHOULD_SAMPLE_SH
		#if UNITY_SAMPLE_FULL_SH_PER_PIXEL
			half3 sh = ShadeSH9(half4(normalWorld, 1.0));
		#elif (SHADER_TARGET >= 30)
			half3 sh = data.ambient + ShadeSH12Order(half4(normalWorld, 1.0));
		#else
			half3 sh = data.ambient;
		#endif
	
		o_gi.indirect.diffuse += sh;
	#endif

	#if !defined(LIGHTMAP_ON)
		o_gi.light = data.light;
		//o_gi.light.color *= data.atten;

	#else
		// Baked lightmaps
		fixed4 bakedColorTex = UNITY_SAMPLE_TEX2D(unity_Lightmap, data.lightmapUV.xy); 
		half3 bakedColor = DecodeLightmap(bakedColorTex);
		
		#ifdef DIRLIGHTMAP_OFF
			o_gi.indirect.diffuse = bakedColor;

			#ifdef SHADOWS_SCREEN
				o_gi.indirect.diffuse = MixLightmapWithRealtimeAttenuation (o_gi.indirect.diffuse, data.atten, bakedColorTex);
			#endif // SHADOWS_SCREEN

		#elif DIRLIGHTMAP_COMBINED
			fixed4 bakedDirTex = UNITY_SAMPLE_TEX2D_SAMPLER (unity_LightmapInd, unity_Lightmap, data.lightmapUV.xy);
			o_gi.indirect.diffuse = DecodeDirectionalLightmap (bakedColor, bakedDirTex, normalWorld);

			#ifdef SHADOWS_SCREEN
				o_gi.indirect.diffuse = MixLightmapWithRealtimeAttenuation (o_gi.indirect.diffuse, data.atten, bakedColorTex);
			#endif // SHADOWS_SCREEN

		#elif DIRLIGHTMAP_SEPARATE
			// Left halves of both intensity and direction lightmaps store direct light; right halves - indirect.

			// Direct
			fixed4 bakedDirTex = UNITY_SAMPLE_TEX2D_SAMPLER(unity_LightmapInd, unity_Lightmap, data.lightmapUV.xy);
			o_gi.indirect.diffuse += DecodeDirectionalSpecularLightmap (bakedColor, bakedDirTex, normalWorld, false, 0, o_gi.light);

			// Indirect
			half2 uvIndirect = data.lightmapUV.xy + half2(0.5, 0);
			bakedColor = DecodeLightmap(UNITY_SAMPLE_TEX2D(unity_Lightmap, uvIndirect));
			bakedDirTex = UNITY_SAMPLE_TEX2D_SAMPLER(unity_LightmapInd, unity_Lightmap, uvIndirect);
			o_gi.indirect.diffuse += DecodeDirectionalSpecularLightmap (bakedColor, bakedDirTex, normalWorld, false, 0, o_gi.light2);
		#endif
	#endif
	
	/*#ifdef DYNAMICLIGHTMAP_ON
		// Dynamic lightmaps
		fixed4 realtimeColorTex = UNITY_SAMPLE_TEX2D(unity_DynamicLightmap, data.lightmapUV.zw);
		half3 realtimeColor = DecodeRealtimeLightmap (realtimeColorTex);

		#ifdef DIRLIGHTMAP_OFF
			o_gi.indirect.diffuse += realtimeColor;

		#elif DIRLIGHTMAP_COMBINED
			half4 realtimeDirTex = UNITY_SAMPLE_TEX2D_SAMPLER(unity_DynamicDirectionality, unity_DynamicLightmap, data.lightmapUV.zw);
			o_gi.indirect.diffuse += DecodeDirectionalLightmap (realtimeColor, realtimeDirTex, normalWorld);

		#elif DIRLIGHTMAP_SEPARATE
			half4 realtimeDirTex = UNITY_SAMPLE_TEX2D_SAMPLER(unity_DynamicDirectionality, unity_DynamicLightmap, data.lightmapUV.zw);
			half4 realtimeNormalTex = UNITY_SAMPLE_TEX2D_SAMPLER(unity_DynamicNormal, unity_DynamicLightmap, data.lightmapUV.zw);
			o_gi.indirect.diffuse += DecodeDirectionalSpecularLightmap (realtimeColor, realtimeDirTex, normalWorld, true, realtimeNormalTex, o_gi.light3);
		#endif
	#endif*/
	o_gi.indirect.diffuse *= occlusion;

#ifndef _DISPLACED_VOLUME
	normalWorld.y *= _PlanarReflectionPack.y;
	normalWorld = normalize(normalWorld);
#endif
	half3 worldNormal = reflect(-data.worldViewDir, normalWorld);

#if defined(_CUBEMAP_REFLECTIONS) && !defined(DEFERRED) && !defined(DEFERRED_SRP)
	if (reflections)
	{
		#if UNITY_SPECCUBE_BOX_PROJECTION		
			half3 worldNormal0 = BoxProjectedCubemapDirection (worldNormal, data.worldPos, data.probePosition[0], data.boxMin[0], data.boxMax[0]);
		#else
			half3 worldNormal0 = worldNormal;
		#endif

		half3 env0 = Unity_GlossyEnvironment (UNITY_PASS_TEXCUBE(unity_SpecCube0), data.probeHDR[0], worldNormal0, 1-oneMinusRoughness);			// !!
		#if UNITY_SPECCUBE_BLENDING
			const float kBlendFactor = 0.99999;
			float blendLerp = data.boxMin[0].w;
			UNITY_BRANCH
			if (blendLerp < kBlendFactor)
			{
				#if UNITY_SPECCUBE_BOX_PROJECTION
					half3 worldNormal1 = BoxProjectedCubemapDirection (worldNormal, data.worldPos, data.probePosition[1], data.boxMin[1], data.boxMax[1]);
				#else
					half3 worldNormal1 = worldNormal;
				#endif

#if UNITY_VERSION < 540
				half3 env1 = Unity_GlossyEnvironment (UNITY_PASS_TEXCUBE_SAMPLER(unity_SpecCube1,unity_SpecCube0), data.probeHDR[1], worldNormal1, 1-oneMinusRoughness);
#else
				half3 env1 = Unity_GlossyEnvironment (UNITY_PASS_TEXCUBE_SAMPLER(unity_SpecCube1, unity_SpecCube0), data.probeHDR[1], worldNormal1, 1-oneMinusRoughness);
#endif
				o_gi.indirect.specular = lerp(env1, env0, blendLerp);
			}
			else
			{
				o_gi.indirect.specular = env0;
			}
		#else
			o_gi.indirect.specular = env0;
		#endif
	}
#endif

	o_gi.indirect.specular *= occlusion;

	PlanarReflection(o_gi, data.screenPos, 1 - oneMinusRoughness, dirRoughness, worldNormal);

	o_gi.indirect.specular *= _ReflectionColor;

#if !defined(_COLLECT_LIGHT_PASS) && !defined(_WATER_BACK)
	//half waterSurfaceDepth = water_depth;
	//half sceneDepth = waterSurfaceDepth - LinearEyeDepthHalf(SAMPLE_DEPTH_TEXTURE_PROJ(_WaterlessDepthTexture, water_refractedScreenPos).r);
	//half predictedDepth = data.worldViewDir.y * sceneDepth;
	//half predictedDepthFactor = exp(min(0, predictedDepth * 0.04));

	half2 localCoord = data.worldPos.xz * _LocalMapsCoords.zz + _LocalMapsCoords.xy;
	half4 subsurfaceScattering = tex2D(_SubsurfaceScattering, localCoord);

#if defined(_WATER_OVERLAYS)
	o_gi.indirect.diffuse = subsurfaceScattering.rgb * subsurfaceScattering.a * (1.0 + (1.0 - water_totalMask.w) * _SubsurfaceScatteringShoreColor);
#else
	o_gi.indirect.diffuse = subsurfaceScattering.rgb * subsurfaceScattering.a;
#endif
#endif

	return o_gi;
}

inline UnityGI UnityGlobalIllumination (UnityGIInput data, half occlusion, half oneMinusRoughness, half3 normalWorld)
{
	return UnityGlobalIllumination (data, occlusion, oneMinusRoughness, normalWorld, true, 1.0 - oneMinusRoughness);	
}

#endif