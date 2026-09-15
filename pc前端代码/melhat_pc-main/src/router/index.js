import { createRouter, createWebHashHistory } from "vue-router";
/* Layout */
import Layout from "@/layout";

/**
 * Note: 路由配置项
 *
 * hidden: true                     // 当设置 true 的时候该路由不会再侧边栏出现 如401，login等页面，或者如一些编辑页面/edit/1
 * alwaysShow: true                 // 当你一个路由下面的 children 声明的路由大于1个时，自动会变成嵌套的模式--如组件页面
 *                                  // 只有一个时，会将那个子路由当做根路由显示在侧边栏--如引导页面
 *                                  // 若你想不管路由下面的 children 声明的个数都显示你的根路由
 *                                  // 你可以设置 alwaysShow: true，这样它就会忽略之前定义的规则，一直显示根路由
 * redirect: noRedirect             // 当设置 noRedirect 的时候该路由在面包屑导航中不可被点击
 * name:'router-name'               // 设定路由的名字，一定要填写不然使用<keep-alive>时会出现各种问题
 * query: '{"id": 1, "name": "ry"}' // 访问路由的默认传递参数
 * roles: ['admin', 'common']       // 访问路由的角色权限
 * permissions: ['a:a:a', 'b:b:b']  // 访问路由的菜单权限
 * meta : {
    noCache: true                   // 如果设置为true，则不会被 <keep-alive> 缓存(默认 false)
    title: 'title'                  // 设置该路由在侧边栏和面包屑中展示的名字
    icon: 'svg-name'                // 设置该路由的图标，对应路径src/assets/icons/svg
    breadcrumb: false               // 如果设置为false，则不会在breadcrumb面包屑中显示
    activeMenu: '/system/user'      // 当路由设置了该属性，则会高亮相对应的侧边栏。
  }
 */

// 公共路由
export const constantRoutes = [
  {
    path: "/redirect",
    component: Layout,
    hidden: true,
    children: [
      {
        path: "/redirect/:path(.*)",
        component: () => import("@/views/redirect/index.vue"),
      },
    ],
  },
  {
    path: "/login",
    component: () => import("@/views/login"),
    hidden: true,
  },
  {
    path: "/:pathMatch(.*)*",
    component: () => import("@/views/error/404"),
    hidden: true,
  },
  {
    path: "/401",
    component: () => import("@/views/error/401"),
    hidden: true,
  },
  {
    path: "/no-site",
    component: () => import("@/views/error/no-site"),
    hidden: true,
    meta: { title: "未授权厂站" },
  },
  {
    path: "/",
    component: Layout,
    hidden: true,
    redirect: "/dashboard",
  },
  {
    path: "/user",
    component: Layout,
    hidden: true,
    redirect: "noredirect",
    children: [
      {
        path: "profile",
        component: () => import("@/views/system/user/profile/index"),
        name: "Profile",
        meta: { title: "个人中心", icon: "user" },
      },
    ]
  },
];

const legacyEnabled = import.meta.env.VITE_ENABLE_LEGACY_CONSOLE === "true";

function loadLegacyRtc() {
  if (window.AgoraRTC) return true;
  return new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = "https://download.agora.io/sdk/release/AgoraRTC_N-4.22.2.js";
    script.onload = () => resolve(true);
    script.onerror = () => reject(new Error("旧版音视频组件加载失败"));
    document.head.appendChild(script);
  });
}

export const legacyRoutes = legacyEnabled ? [
  {
    path: "/legacy/big-screen",
    component: () => import("@/views/big-screen/index.vue"),
    hidden: true,
    meta: { title: "旧版数据大屏", legacy: true },
  },
  {
    path: "/legacy",
    component: Layout,
    hidden: true,
    children: [
      { path: "group", component: () => import("@/views/group/index.vue"), name: "LegacyGroup", meta: { title: "旧版群组", legacy: true } },
      { path: "hat", component: () => import("@/views/hat/index.vue"), name: "LegacyHat", meta: { title: "旧版帽子", legacy: true } },
      { path: "live", component: () => import("@/views/live/index.vue"), beforeEnter: loadLegacyRtc, name: "LegacyLive", meta: { title: "旧版实时监控", legacy: true } },
      { path: "events", component: () => import("@/views/events/index.vue"), beforeEnter: loadLegacyRtc, name: "LegacyEvents", meta: { title: "旧版事件操作", legacy: true } },
      { path: "duty", component: () => import("@/views/duty/index.vue"), name: "LegacyDuty", meta: { title: "旧版值班交接", legacy: true } },
      { path: "locations", component: () => import("@/views/locations/index.vue"), name: "LegacyLocations", meta: { title: "旧版定位", legacy: true } },
      { path: "track", component: () => import("@/views/track/index.vue"), name: "LegacyTrack", meta: { title: "旧版轨迹", legacy: true } },
      { path: "fence", component: () => import("@/views/fence/index.vue"), name: "LegacyFence", meta: { title: "旧版围栏", legacy: true } },
      { path: "sos", component: () => import("@/views/sos/index.vue"), name: "LegacySos", meta: { title: "旧版告警", legacy: true } },
      { path: "files", component: () => import("@/views/file/index.vue"), name: "LegacyFiles", meta: { title: "旧版文件", legacy: true } },
      { path: "intercom", component: () => import("@/views/intercom/index.vue"), name: "LegacyIntercom", meta: { title: "旧版对讲", legacy: true } },
      { path: "tts", component: () => import("@/views/tts/index.vue"), name: "LegacyTts", meta: { title: "旧版广播", legacy: true } },
    ],
  },
] : [];

// 动态路由，基于用户权限动态去加载
export const dynamicRoutes = [
  {
    path: "/system/user-auth",
    component: Layout,
    hidden: true,
    permissions: ["system:user:edit"],
    children: [
      {
        path: "role/:userId(\\d+)",
        component: () => import("@/views/system/user/authRole"),
        name: "AuthRole",
        meta: { title: "分配角色", activeMenu: "/system/user" },
      },
    ],
  },
  {
    path: "/system/role-auth",
    component: Layout,
    hidden: true,
    permissions: ["system:role:edit"],
    children: [
      {
        path: "user/:roleId(\\d+)",
        component: () => import("@/views/system/role/authUser"),
        name: "AuthUser",
        meta: { title: "分配用户", activeMenu: "/system/role" },
      },
    ],
  },
  {
    path: "/system/dict-data",
    component: Layout,
    hidden: true,
    permissions: ["system:dict:list"],
    children: [
      {
        path: "index/:dictId(\\d+)",
        component: () => import("@/views/system/dict/data"),
        name: "Data",
        meta: { title: "字典数据", activeMenu: "/system/dict" },
      },
    ],
  },
];

const router = createRouter({
  history: createWebHashHistory(),
  routes: constantRoutes,
  scrollBehavior(to, from, savedPosition) {
    if (savedPosition) {
      return savedPosition;
    } else {
      return { top: 0 };
    }
  },
});

export default router;
