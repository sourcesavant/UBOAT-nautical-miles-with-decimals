#ifndef TERRAIN_SPLATMAP_COMMON_CGINC_INCLUDED
#define TERRAIN_SPLATMAP_COMMON_CGINC_INCLUDED

#if defined(_NORMALMAP) && !defined(_TERRAIN_NORMAL_MAP)
    #define _TERRAIN_NORMAL_MAP
#elif !defined(_NORMALMAP) && defined(_TERRAIN_NORMAL_MAP)
    #define _NORMALMAP
#endif

#define COMPENSATE_EARTH_CURVATURE_PER_VERTEX 1
#include "Packages/PlayWay Water/Shaders/Includes/EarthCurvature.cginc"

struct Input
{
	float2 uv_Splat0 : TEXCOORD0;
	float2 uv_Splat1 : TEXCOORD1;
	float2 uv_Splat2 : TEXCOORD2;
	float2 uv_Splat3 : TEXCOORD3;
#if defined(TERRAIN_INSTANCED_PERPIXEL_NORMAL)
	float4 tc_Control : TEXCOORD4;	// Not prefixing '_Contorl' with 'uv' allows a tighter packing of interpolators, which is necessary to support directional lightmap.
#else
	float2 tc_Control : TEXCOORD4;
#endif
	float elevation : TEXCOORD5;
};

sampler2D _Control;
float4 _Control_ST;
//float4 _TerrainOffset;
float _NormalScale;
half _GlobalMapAlbedoMix;
half _GlobalMapHeightmapMix;
sampler2D _Splat0,_Splat1,_Splat2,_Splat3,_Splat4;

#ifdef _TERRAIN_NORMAL_MAP
	sampler2D _Normal0, _Normal1, _Normal2, _Normal3, _Normal4;
#endif

#ifdef HEIGHTMAP
	sampler2D _Heightmap;
	half4 _Heightmap_TexelSize;
#endif

#if defined(UNITY_INSTANCING_ENABLED) && !defined(SHADER_API_D3D11_9X)
    Texture2D _TerrainHeightmapTexture;
	#if defined(TERRAIN_INSTANCED_PERPIXEL_NORMAL)
		sampler2D _TerrainNormalmapTexture;
	#else
		Texture2D _TerrainNormalmapTexture;
	#endif
    float4    _TerrainHeightmapRecipSize;   // float4(1.0f/width, 1.0f/height, 1.0f/(width-1), 1.0f/(height-1))
    float4    _TerrainHeightmapScale;       // float4(hmScale.x, hmScale.y / (float)(kMaxHeight), hmScale.z, 0.0f)
#endif

UNITY_INSTANCING_BUFFER_START(Terrain)
    UNITY_DEFINE_INSTANCED_PROP(float4, _TerrainPatchInstanceData) // float4(xBase, yBase, skipScale, ~)
UNITY_INSTANCING_BUFFER_END(Terrain)

	inline half2 approxTanh(half2 x)
	{
		return x / sqrt(1.0 + x * x);
	}

void SplatmapVert(inout appdata_full v, out Input data)
{
	UNITY_INITIALIZE_OUTPUT(Input, data);
	
#if defined(UNITY_INSTANCING_ENABLED) && !defined(SHADER_API_D3D11_9X)

    float2 patchVertex = v.vertex.xy;
    float4 instanceData = UNITY_ACCESS_INSTANCED_PROP(Terrain, _TerrainPatchInstanceData);

    float4 uvscale = instanceData.z * _TerrainHeightmapRecipSize;
    float4 uvoffset = instanceData.xyxy * uvscale;
    uvoffset.xy += 0.5f * _TerrainHeightmapRecipSize.xy;
    float2 sampleCoords = (patchVertex.xy * uvscale.xy + uvoffset.xy);
	float2 sampleCoords2 = (patchVertex.xy + instanceData.xy) * instanceData.z;

    float hm = UnpackHeightmap(_TerrainHeightmapTexture.Load(int3(sampleCoords2, 0)));
    v.vertex.xz = (patchVertex.xy + instanceData.xy) * _TerrainHeightmapScale.xz * instanceData.z;  //(x + xBase) * hmScale.x * skipScale;
    v.vertex.y = hm * _TerrainHeightmapScale.y;
    v.vertex.w = 1.0f;

    v.texcoord.xy = (patchVertex.xy * uvscale.zw + uvoffset.zw);
    v.texcoord3 = v.texcoord2 = v.texcoord1 = v.texcoord;

    #ifdef TERRAIN_INSTANCED_PERPIXEL_NORMAL
        v.normal = float3(0, 1, 0); // TODO: reconstruct the tangent space in the pixel shader. Seems to be hard with surface shader especially when other attributes are packed together with tSpace.
        data.tc_Control.zw = sampleCoords;
    #else
        float3 nor = _TerrainNormalmapTexture.Load(int3(sampleCoords2, 0)).xyz;
        v.normal = 2.0f * nor - 1.0f;
    #endif
#endif
	
	data.tc_Control.xy = TRANSFORM_TEX(v.texcoord, _Control);	// Need to manually transform uv here, as we choose not to use 'uv' prefix for this texcoord.
	//v.vertex += _TerrainOffset;
#if defined(HEIGHTMAP)
	v.texcoord.xy = (v.texcoord.xy * (_Heightmap_TexelSize.zw - 1) + 0.5) / _Heightmap_TexelSize.zw;

	float minElevation = lerp(0.0, 600 / 3200.0f, _GlobalMapHeightmapMix);
	float elevation = max(minElevation, tex2Dlod(_Heightmap, v.texcoord));
	v.vertex.y += elevation;
	data.elevation = elevation * 3200 - 600;

	/*v.normal.x = max(600 / 3200, elevation) - max(600 / 3200, tex2Dlod(_Heightmap, v.texcoord + float4(_Heightmap_TexelSize.x, 0, 0, 0)));
	v.normal.z = max(600 / 3200, elevation) - max(600 / 3200, tex2Dlod(_Heightmap, v.texcoord + float4(0, _Heightmap_TexelSize.y, 0, 0)));
	v.normal.xz = v.normal.xz  * 15000000.0 * _NormalScale;
	v.normal.y = 0.08;
	v.normal = normalize(v.normal);*/

#else
	data.elevation = v.vertex.y - 600.0;
#endif
	v.vertex.y = CompensateForEarthCurvature(v.vertex + float4(unity_ObjectToWorld[0].w, 0.0, unity_ObjectToWorld[2].w, 0.0)).y;

#ifdef _TERRAIN_NORMAL_MAP
	v.tangent.xyz = cross(v.normal, float3(0,0,1));
	v.tangent.w = -1;
#endif
}

#ifdef TERRAIN_STANDARD_SHADER
void SplatmapMix(Input IN, half4 defaultAlpha, out half4 splat_control, out half weight, out fixed4 mixedDiffuse, inout fixed3 mixedNormal)
#else
void SplatmapMix(Input IN, out half4 splat_control, out half weight, out fixed4 mixedDiffuse, inout fixed3 mixedNormal)
#endif
{
	splat_control = tex2D(_Control, IN.tc_Control.xy);

#if !defined(DONT_USE_ELEVATION_DATA)
	half beach = saturate((4.5 - IN.elevation) * 0.075 - splat_control.b);
	splat_control.g += beach;
	splat_control.r = max(0.0, splat_control.r - beach);
#endif

	weight = dot(splat_control, half4(1,1,1,1));

	/*float newRock = splat_control.b * splat_control.b;

	if(splat_control.b > 0.000001)
		splat_control.rgb /= (1.0 - (splat_control.b - newRock));

	splat_control.b = newRock;*/

	#if !defined(SHADER_API_MOBILE) && defined(TERRAIN_SPLAT_ADDPASS)
		clip(weight == 0.0f ? -1 : 1);
	#endif

	// Normalize weights before lighting and restore weights in final modifier functions so that the overal
	// lighting result can be correctly weighted.
	//splat_control /= (weight + 1e-3f);
	half fifthTexIntensity = 1.0 - weight;
	half distance = _WorldSpaceCameraPos.y;

	mixedDiffuse = 0.0f;
	#ifdef TERRAIN_STANDARD_SHADER
		mixedDiffuse += splat_control.r * lerp(tex2D(_Splat0, IN.uv_Splat0), tex2D(_Splat0, IN.uv_Splat0 * 0.12), saturate((distance - 100) / 1200))/* * half4(1.0, 1.0, 1.0, defaultAlpha.r)*/;
		mixedDiffuse += splat_control.g * tex2D(_Splat1, IN.uv_Splat1)/* * half4(1.0, 1.0, 1.0, defaultAlpha.g)*/;
		mixedDiffuse += splat_control.b * tex2D(_Splat2, IN.uv_Splat2)/* * half4(1.0, 1.0, 1.0, defaultAlpha.b)*/;
		mixedDiffuse += splat_control.a * tex2D(_Splat3, IN.uv_Splat3)/* * half4(1.0, 1.0, 1.0, defaultAlpha.a)*/;
		mixedDiffuse += fifthTexIntensity * tex2D(_Splat4, IN.uv_Splat3 * 0.007);
	#else
		mixedDiffuse += splat_control.r * tex2D(_Splat0, IN.uv_Splat0);
		mixedDiffuse += splat_control.g * tex2D(_Splat1, IN.uv_Splat1);
		mixedDiffuse += splat_control.b * tex2D(_Splat2, IN.uv_Splat2);
		mixedDiffuse += splat_control.a * tex2D(_Splat3, IN.uv_Splat3);
		mixedDiffuse += fifthTexIntensity * tex2D(_Splat4, IN.uv_Splat3 * 0.007);
	#endif

	#ifdef _TERRAIN_NORMAL_MAP
		fixed4 nrm = 0.0f;
		nrm += splat_control.r * tex2D(_Normal0, IN.uv_Splat0);
		nrm += splat_control.g * tex2D(_Normal1, IN.uv_Splat1);
		nrm += splat_control.b * tex2D(_Normal2, IN.uv_Splat2);
		nrm += splat_control.a * tex2D(_Normal3, IN.uv_Splat3);
		nrm += fifthTexIntensity * tex2D(_Normal4, IN.uv_Splat3 * 0.007);
		mixedNormal = UnpackNormal(nrm);
	#endif

	#if defined(INSTANCING_ON) && defined(SHADER_TARGET_SURFACE_ANALYSIS) && defined(TERRAIN_INSTANCED_PERPIXEL_NORMAL)
        mixedNormal = float3(0, 0, 1); // make sure that surface shader compiler realizes we write to normal, as UNITY_INSTANCING_ENABLED is not defined for SHADER_TARGET_SURFACE_ANALYSIS.
    #endif

	#if defined(UNITY_INSTANCING_ENABLED) && !defined(SHADER_API_D3D11_9X) && defined(TERRAIN_INSTANCED_PERPIXEL_NORMAL)
        float3 geomNormal = normalize(tex2D(_TerrainNormalmapTexture, IN.tc_Control.zw).xyz * 2 - 1);
        #ifdef _TERRAIN_NORMAL_MAP
            float3 geomTangent = normalize(cross(geomNormal, float3(0, 0, 1)));
            float3 geomBitangent = normalize(cross(geomTangent, geomNormal));
            mixedNormal = mixedNormal.x * geomTangent
                          + mixedNormal.y * geomBitangent
                          + mixedNormal.z * geomNormal;
        #else
            mixedNormal = geomNormal;
        #endif
        mixedNormal = mixedNormal.xzy;
	#endif
}

#ifndef TERRAIN_SURFACE_OUTPUT
	#define TERRAIN_SURFACE_OUTPUT SurfaceOutput
#endif

void SplatmapFinalColor(Input IN, TERRAIN_SURFACE_OUTPUT o, inout fixed4 color)
{
	color *= o.Alpha;
}

void SplatmapFinalPrepass(Input IN, TERRAIN_SURFACE_OUTPUT o, inout fixed4 normalSpec)
{
	normalSpec *= o.Alpha;
}

void SplatmapFinalGBuffer(Input IN, TERRAIN_SURFACE_OUTPUT o, inout half4 diffuse, inout half4 specSmoothness, inout half4 normal, inout half4 emission)
{
	diffuse.rgb *= o.Alpha;
	specSmoothness *= o.Alpha;
	normal.rgb *= o.Alpha;
	emission *= o.Alpha;
}

#endif // TERRAIN_SPLATMAP_COMMON_CGINC_INCLUDED
