"""Image preprocessing contracts; end-to-end RTL comparison is in demo_smoke.py."""
import numpy as np
import pytest
from PIL import Image
from scripts.predict import prepare_image


def test_light_and_dark_digits_agree(tmp_path):
    x=np.zeros((8,8),dtype=np.uint8);x[1:7,3:5]=255
    Image.fromarray(x).save(tmp_path/'light.png')
    Image.fromarray(255-x).save(tmp_path/'dark.png')
    light,inv_l=prepare_image(tmp_path/'light.png')
    dark,inv_d=prepare_image(tmp_path/'dark.png')
    assert isinstance(inv_l,bool) and isinstance(inv_d,bool)
    assert not inv_l and inv_d
    np.testing.assert_array_equal(light,dark)
    np.testing.assert_array_equal(light.reshape(8,8),x/255)


def test_aspect_ratio_padding_and_transparency(tmp_path):
    # Transparent background becomes white; opaque black is the stroke.
    x=np.zeros((16,4,4),dtype=np.uint8);x[2:14,:,3]=255
    Image.fromarray(x).save(tmp_path/'rgba.png')
    values,inverted=prepare_image(tmp_path/'rgba.png','dark')
    assert inverted and values.shape==(64,)
    assert 0<=values.min()<=values.max()<=1
    assert values.reshape(8,8)[:,0].max()<=1/255  # Lanczos edge ringing
    assert values.max()>0


def test_invalid_image_fails(tmp_path):
    path=tmp_path/'bad.png';path.write_bytes(b'not a picture')
    with pytest.raises(OSError):prepare_image(path)
