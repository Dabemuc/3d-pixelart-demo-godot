class_name PixelArtBuffers

const TARGET_SIZE := Vector2i(640, 360)

static var _color: RID
static var _depth: RID
static var _normal: RID
static var _mask: RID

static func ensure_color(rd: RenderingDevice) -> RID:
	if not _color.is_valid():
		_color = _create_texture(rd, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
	return _color

static func ensure_depth(rd: RenderingDevice) -> RID:
	if not _depth.is_valid():
		_depth = _create_texture(rd, RenderingDevice.DATA_FORMAT_R32_SFLOAT)
	return _depth

static func ensure_normal(rd: RenderingDevice) -> RID:
	if not _normal.is_valid():
		_normal = _create_texture(rd, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
	return _normal

static func ensure_mask(rd: RenderingDevice) -> RID:
	if not _mask.is_valid():
		_mask = _create_texture(rd, RenderingDevice.DATA_FORMAT_R8G8_UNORM)
	return _mask

static func _create_texture(rd: RenderingDevice, format: RenderingDevice.DataFormat) -> RID:
	var tf := RDTextureFormat.new()
	tf.format = format
	tf.width = TARGET_SIZE.x
	tf.height = TARGET_SIZE.y
	tf.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	return rd.texture_create(tf, RDTextureView.new())
