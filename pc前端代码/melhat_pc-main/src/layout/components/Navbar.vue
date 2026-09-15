<template>
  <div class="navbar">
    <hamburger
      id="hamburger-container"
      class="hamburger-container"
      :is-active="appStore.sidebar.opened"
      @toggleClick="toggleSideBar"
    />
    <breadcrumb
      v-if="!settingsStore.topNav"
      id="breadcrumb-container"
      class="breadcrumb-container"
    />
    <top-nav
      v-if="settingsStore.topNav"
      id="topmenu-container"
      class="topmenu-container"
    />

    <div class="right-menu">
      <el-select
        v-if="userStore.sites && userStore.sites.length"
        class="site-switch"
        :model-value="userStore.currentSiteId"
        placeholder="选择厂站"
        @change="onSiteChange"
      >
        <el-option
          v-for="site in userStore.sites"
          :key="site.id"
          :label="site.name"
          :value="site.id"
        />
      </el-select>
      <div class="avatar-container">
        <el-dropdown
          class="right-menu-item hover-effect"
          trigger="click"
          @command="handleCommand"
        >
          <div class="avatar-wrapper">
            <img class="user-avatar" :src="userStore.avatar" alt="用户头像" />
            <span class="user-name">{{ userStore.name || '管理员' }}</span>
            <el-icon><caret-bottom /></el-icon>
          </div>
          <template #dropdown>
            <el-dropdown-menu>
              <router-link to="/user/profile">
                <el-dropdown-item>个人中心</el-dropdown-item>
              </router-link>
              <el-dropdown-item command="logout">
                <span>退出登录</span>
              </el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
      </div>
    </div>
  </div>
</template>

<script setup>
import Breadcrumb from "@/components/Breadcrumb";
import Hamburger from "@/components/Hamburger";
import TopNav from "@/components/TopNav";
import useAppStore from "@/store/modules/app";
import useSettingsStore from "@/store/modules/settings";
import useUserStore from "@/store/modules/user";
import { ElMessageBox } from "element-plus";

const appStore = useAppStore();
const userStore = useUserStore();
const settingsStore = useSettingsStore();
const router = useRouter();

function toggleSideBar() {
  appStore.toggleSideBar();
}

function handleCommand(command) {
  switch (command) {
    case "setLayout":
      setLayout();
      break;
    case "logout":
      logout();
      break;
    default:
      break;
  }
}

function onSiteChange(siteId) {
  userStore.switchSite(siteId).then(() => {
    window.dispatchEvent(new CustomEvent("site-changed", { detail: siteId }));
  });
}

function logout() {
  ElMessageBox.confirm("确定注销并退出系统吗？", "提示", {
    confirmButtonText: "确定",
    cancelButtonText: "取消",
    type: "warning",
  })
    .then(() => {
      userStore.logOut().then(() => {
        router.replace("/login");
      }).catch(() => {
        router.replace("/login");
      });
    })
    .catch(() => {});
}

const emits = defineEmits(["setLayout"]);
function setLayout() {
  emits("setLayout");
}
</script>

<style lang="scss" scoped>
.navbar {
  height: 56px;
  overflow: hidden;
  position: relative;
  background: var(--bg-pure);
  border-bottom: 1px solid var(--border-color);
  display: flex;
  align-items: center;
  padding: 0 18px;

  .site-switch {
    width: 180px;
    margin-right: 16px;
  }

  .hamburger-container {
    line-height: 56px;
    height: 100%;
    float: left;
    cursor: pointer;
    transition: background 0.3s;
    color: var(--text-secondary);
    -webkit-tap-highlight-color: transparent;
    display: flex;
    align-items: center;
    width: 36px;
    padding: 0;
    margin-left: -8px;
    border-radius: 8px;

    &:hover {
      background: var(--bg-soft);
      color: var(--text-primary);
    }
  }

  .breadcrumb-container {
    float: left;
    margin-left: 8px;
  }

  .topmenu-container {
    position: absolute;
    left: 70px;
  }

  .errLog-container {
    display: inline-block;
    vertical-align: top;
  }

  .right-menu {
    margin-left: auto;
    display: flex;
    align-items: center;
      gap: 6px;

    &:focus {
      outline: none;
    }

    .right-menu-item {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      padding: 0;
      height: 36px;
      font-size: 18px;
      color: var(--text-secondary);
      vertical-align: text-bottom;
      border-radius: 8px;
      transition: all 0.15s;

      &.hover-effect {
        cursor: pointer;

        &:hover {
          background: var(--bg-soft);
          color: var(--text-primary);
        }
      }
    }

    .avatar-container {
      margin-right: 0;
      margin-left: 4px;
      display: flex;
      align-items: center;
      gap: 8px;

      .avatar-wrapper {
        position: relative;
        display: flex;
        align-items: center;
        gap: 8px;
        height: 40px;
        padding: 3px 8px 3px 4px;
        border-radius: 4px;
        transition: background 0.15s;

        &:hover {
          background: var(--bg-hover);
        }

        .user-avatar {
          cursor: pointer;
          width: 32px;
          height: 32px;
          border-radius: 4px;
          border: 1px solid var(--border-color);
        }

        .user-name {
          max-width: 96px;
          overflow: hidden;
          color: var(--text-primary);
          font-size: 13px;
          font-weight: 550;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        i {
          cursor: pointer;
          font-size: 12px;
          color: var(--text-muted);
        }
      }
    }
  }
}

@media (max-width: 1200px) {
  .navbar .right-menu .avatar-container {
    .user-name {
      display: none;
    }
  }
}
</style>
