#include <linux/module.h>
#define INCLUDE_VERMAGIC
#include <linux/build-salt.h>
#include <linux/elfnote-lto.h>
#include <linux/vermagic.h>
#include <linux/compiler.h>

BUILD_SALT;
BUILD_LTO_INFO;

MODULE_INFO(vermagic, VERMAGIC_STRING);
MODULE_INFO(name, KBUILD_MODNAME);

__visible struct module __this_module
__section(".gnu.linkonce.this_module") = {
	.name = KBUILD_MODNAME,
	.init = init_module,
#ifdef CONFIG_MODULE_UNLOAD
	.exit = cleanup_module,
#endif
	.arch = MODULE_ARCH_INIT,
};

#ifdef CONFIG_RETPOLINE
MODULE_INFO(retpoline, "Y");
#endif

static const struct modversion_info ____versions[]
__used __section("__versions") = {
	{ 0x5cee3687, "module_layout" },
	{ 0x92da9918, "param_ops_charp" },
	{ 0xc6bde948, "param_ops_int" },
	{ 0x660c47c2, "param_ops_uint" },
	{ 0xbaecb1d6, "video_ioctl2" },
	{ 0x365099f7, "vb2_ops_wait_finish" },
	{ 0x42aa7cf1, "vb2_ops_wait_prepare" },
	{ 0x478e2c9d, "vf_unreg_receiver" },
	{ 0xf8beca97, "cancel_delayed_work_sync" },
	{ 0x596b16e2, "platform_device_unregister" },
	{ 0x3f4cba67, "v4l2_device_unregister" },
	{ 0x9e42ff8e, "video_unregister_device" },
	{ 0x4ebb0493, "vf_reg_receiver" },
	{ 0x90a5e877, "vf_receiver_init" },
	{ 0x67b9718c, "__video_register_device" },
	{ 0x4a8d99e8, "video_device_release_empty" },
	{ 0x8fb5feac, "v4l2_device_register" },
	{ 0x894bd595, "dma_set_mask" },
	{ 0x5793eacd, "dma_set_coherent_mask" },
	{ 0x79cf5987, "init_timer_key" },
	{ 0x253af43d, "delayed_work_timer_fn" },
	{ 0xd9a5ea54, "__init_waitqueue_head" },
	{ 0xb1c4e299, "platform_device_register" },
	{ 0xd969d6f4, "cancel_work_sync" },
	{ 0xe2c5cb8c, "vf_unreg_provider" },
	{ 0xb5b54b34, "_raw_spin_unlock" },
	{ 0xba8fbd64, "_raw_spin_lock" },
	{ 0x3eeb2322, "__wake_up" },
	{ 0x732ac580, "queue_work_on" },
	{ 0xb40185d1, "vf_get" },
	{ 0xd35cbb98, "vf_peek" },
	{ 0x7e2c5f37, "dma_buf_export" },
	{ 0xb43f9365, "ktime_get" },
	{ 0x79a6c473, "dma_buf_fd" },
	{ 0x4735ac17, "flush_work" },
	{ 0xc8b93892, "vf_reg_provider" },
	{ 0x1ffd42e2, "vf_provider_init" },
	{ 0xaa408e8, "vf_get_receiver" },
	{ 0xbf57e89e, "queue_delayed_work_on" },
	{ 0x2d3385d3, "system_wq" },
	{ 0xe112197, "tvin_get_sm_status" },
	{ 0x29965b45, "vf_notify_provider" },
	{ 0xda44a03, "vf_put" },
	{ 0xd14fef22, "cpu_hwcap_keys" },
	{ 0x14b89635, "arm64_const_caps_ready" },
	{ 0x68f31cbd, "__list_add_valid" },
	{ 0x2ca8f50d, "v4l2_fh_add" },
	{ 0xab090825, "vb2_queue_init" },
	{ 0xe6865b64, "vb2_dma_contig_memops" },
	{ 0x7b840a27, "v4l2_fh_init" },
	{ 0xa571f6b0, "__mutex_init" },
	{ 0xe6bf841d, "video_devdata" },
	{ 0x9688de8b, "memstart_addr" },
	{ 0x3a2f6702, "sg_alloc_table" },
	{ 0xa12e7fe8, "kmem_cache_alloc_trace" },
	{ 0xcf8fae34, "kmalloc_caches" },
	{ 0x1c8f2f40, "v4l2_fh_exit" },
	{ 0x57cf0102, "v4l2_fh_del" },
	{ 0xed55cabd, "mutex_unlock" },
	{ 0xd5977bfb, "mutex_lock" },
	{ 0xce33a2b9, "vb2_queue_release" },
	{ 0x77026136, "vb2_buffer_done" },
	{ 0xdde9969f, "dma_buf_put" },
	{ 0xe1537255, "__list_del_entry_valid" },
	{ 0x3ea1b6e4, "__stack_chk_fail" },
	{ 0xc66b9505, "v4l2_event_queue" },
	{ 0xdcb764ad, "memset" },
	{ 0x4cbaf6e8, "v4l_get_dev_from_codec_mm" },
	{ 0x37c3bad8, "v4l2_src_change_event_subscribe" },
	{ 0x9f48e1bf, "v4l2_event_subscribe" },
	{ 0x3c17cdbc, "vf_notify_receiver" },
	{ 0x37a0cba, "kfree" },
	{ 0x7f5b4fe4, "sg_free_table" },
	{ 0x9943837, "remap_pfn_range" },
	{ 0x2dbd35c9, "v4l2_event_pending" },
	{ 0xf8fe69c0, "vb2_poll" },
	{ 0x9b31441d, "vb2_mmap" },
	{ 0x28e28f68, "vb2_reqbufs" },
	{ 0xa2234f4d, "vb2_querybuf" },
	{ 0x7481f05b, "vb2_qbuf" },
	{ 0xf326b057, "vb2_expbuf" },
	{  0x2a5c1, "vb2_dqbuf" },
	{ 0xd09a1184, "vb2_streamon" },
	{ 0x91c10db6, "vb2_streamoff" },
	{ 0x76ec80f, "v4l2_event_unsubscribe" },
	{ 0x96848186, "scnprintf" },
	{ 0xdd64e639, "strscpy" },
	{ 0x92997ed8, "_printk" },
	{ 0xd35cce70, "_raw_spin_unlock_irqrestore" },
	{ 0x34db050b, "_raw_spin_lock_irqsave" },
};

MODULE_INFO(depends, "aml_media");


MODULE_INFO(scmversion, "g39962dae2b27-dirty");
