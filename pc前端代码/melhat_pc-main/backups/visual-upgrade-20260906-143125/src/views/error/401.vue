<template>
  <div class="errPage-container">
    <el-button class="pan-back-btn" icon="arrow-left" @click="back">
      返回
    </el-button>
    <el-row>
      <el-col :span="12">
        <h1 class="text-jumbo text-ginormous">
          401错误!
        </h1>
        <h2>您没有访问权限！</h2>
        <h6>对不起，您没有访问权限，请不要进行非法操作！您可以返回主页面</h6>
        <ul class="list-unstyled">
          <li class="link-type">
            <router-link to="/">
              回首页
            </router-link>
          </li>
        </ul>
      </el-col>
      <el-col :span="12">
        <img alt="Girl has dropped her ice cream." height="428" :src="errGif" width="313">
      </el-col>
    </el-row>
  </div>
</template>

<script setup>
import errImage from "@/assets/401_images/401.gif";

let { proxy } = getCurrentInstance();

const errGif = ref(errImage + "?" + +new Date());

function back() {
  if (proxy.$route.query.noGoBack) {
    proxy.$router.push({ path: "/" });
  } else {
    proxy.$router.go(-1);
  }
}
</script>

<style lang="scss" scoped>
.errPage-container {
  width: min(920px, calc(100% - 40px));
  max-width: 100%;
  margin: 8vh auto;
  padding: 40px;
  border: 1px solid var(--border-color);
  border-radius: 14px;
  background: var(--bg-pure);
  box-shadow: var(--shadow-lg);
  .pan-back-btn {
    background: var(--color-primary);
    color: #fff;
    border: none;
  }
  .pan-gif {
    margin: 0 auto;
    display: block;
  }
  .pan-img {
    display: block;
    margin: 0 auto;
    width: 100%;
  }
  .text-jumbo {
    margin: 40px 0 12px;
    font-size: 54px;
    font-weight: 650;
    color: var(--text-primary);
  }
  .list-unstyled {
    font-size: 14px;
    li {
      padding-bottom: 5px;
    }
    a {
      color: var(--color-primary);
      text-decoration: none;
      &:hover {
        text-decoration: underline;
      }
    }
  }

  h2 {
    color: var(--text-primary);
  }

  h6 {
    color: var(--text-secondary);
    font-size: 14px;
    font-weight: 400;
    line-height: 1.7;
  }
}

@media (max-width: 768px) {
  .errPage-container {
    margin: 20px auto;
    padding: 24px;

    :deep(.el-col) {
      width: 100%;
      max-width: 100%;
      flex: 0 0 100%;
    }
  }
}
</style>
