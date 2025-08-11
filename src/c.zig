pub usingnamespace @cImport({
    @cDefine("STBI_NO_GIF", "1");
    @cDefine("STBI_NO_JPEG", "1");
    @cDefine("STBI_NO_HDR", "1");
    @cDefine("STBI_NO_TGA", "1");
    @cDefine("STB_IMAGE_IMPLEMENTATION", "1");
    @cInclude("stb_image.h");
});
